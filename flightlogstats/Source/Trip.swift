//
//  Trip.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 04/08/2022.
//

import Foundation
import RZFlight
import RZUtils
import RZUtilsSwift

struct Trip {
    typealias Field = FlightSummary.Field
    /// infos in the trips sorted from newest to oldest
    var flightLogFileInfos : [FlightLogFileInfo] = []
    var count : Int { return self.flightLogFileInfos.count }
    var stats : [Field:ValueStats] = [:]
    
    var empty : Bool { return self.flightLogFileInfos.count == 0 }
    
    enum Aggregation {
        case awayFromBase(Airport)
        case calendarUnit(GCStatsDateBuckets)
    }
    
    var label : String
    
    private let aggregation : Aggregation
    
    init(base: Airport) {
        self.aggregation = .awayFromBase(base)
        self.label = "Trip"
    }
    
    init(unit : NSCalendar.Unit, referenceDate : Date? = nil){
        let bucket = GCStatsDateBuckets(for: unit, referenceDate: referenceDate, andCalendar: Calendar.current)
        self.init(bucket: bucket)
    }
    
    private init(bucket : GCStatsDateBuckets) {
        self.aggregation = .calendarUnit(bucket)
        self.label = bucket.description
    }
    
    private mutating func add(summary : FlightSummary){
        for field in FlightSummary.Field.allCases {
            if let nu = summary.numberWithUnit(for: field) {
                if stats[field] == nil {
                    stats[field] = ValueStats(numberWithUnit: nu)
                }else{
                    stats[field]?.update(numberWithUnit: nu)
                }
            }
        }
    }
    
    private mutating func add(base : Airport, info : FlightLogFileInfo) -> Bool {
        var rv = false
        if let summary = info.flightSummary,
           let startAirport = summary.startAirport,
           let endAirport = summary.endAirport{
            
            if let last = self.flightLogFileInfos.last {
                if last.isNewer(than: info) && startAirport == base{
                    rv = true
                }
                if !last.isNewer(than: info) && endAirport == base {
                    rv = true
                }
            }
            
            self.add(summary: summary)
            
            flightLogFileInfos.append(info)
            flightLogFileInfos.sort {
                $0.isNewer(than: $1)
            }
        }
        return rv
    }
    
    private mutating func add(bucket : GCStatsDateBuckets, info : FlightLogFileInfo) -> Bool {
        var rv = false
        if let summary = info.flightSummary,
           let start = summary.hobbs?.start {
            if self.self.flightLogFileInfos.count == 0 {
                flightLogFileInfos.append(info)
                bucket.bucket(start)
            }else{
                if bucket.contains(start) {
                    self.add(summary: summary)
                    flightLogFileInfos.append(info)
                    flightLogFileInfos.sort {
                        $0.isNewer(than: $1)
                    }
                    
                }else{
                    rv = true
                }
            }
        }
        
        return rv
    }
    
    /// Add the info to the trip
    /// - Parameter info: info to add
    /// - Returns: true if this info concludes the trip
    mutating func add(info : FlightLogFileInfo) -> Bool {
        switch aggregation {
        case .awayFromBase(let base):
            return self.add(base: base, info: info)
        case .calendarUnit(let bucket):
            return self.add(bucket: bucket, info: info)
        }
    }
    
    func next(info: FlightLogFileInfo) -> Trip? {
        switch self.aggregation {
        case .awayFromBase(let base):
            return Trip(base: base)
        case .calendarUnit(let bucket):
            if let summary = info.flightSummary,
               let start = summary.hobbs?.start {
                bucket.bucket(start)
                var rv = Trip(bucket: bucket)
                rv.add(summary: summary)
                rv.flightLogFileInfos = [info]
                return rv
            }
            return nil
        }
    }
    
    func numberWithUnit(field : Field) -> GCNumberWithUnit? {
        if let stats = self.stats[field] {
            switch field {
            case .FuelStart:
                return nil
            case .FuelEnd:
                return nil
            case .FuelUsed,.FuelTotalizer:
                return stats.sumWithUnit
            case .Distance:
                return stats.sumWithUnit
            case .Altitude:
                return stats.maxWithUnit
            case .Hobbs,.Flying,.Moving:
                return stats.sumWithUnit
            case .GroundSpeed:
                if let dist = self.stats[.Distance]?.sumWithUnit.convert(to: GCUnit.nm()),
                   let flying = self.stats[.Flying]?.sumWithUnit.convert(to: GCUnit.second()),
                   let moving = self.stats[.Moving]?.sumWithUnit.convert(to: GCUnit.second()) {
                    var elapsed = flying
                    do {
                        let nonflying = try moving - flying
                        if nonflying > flying {
                            elapsed = moving
                        }
                    }
                    catch {
                        return nil
                    }
                    return GCNumberWithUnit(unit: GCUnit.knot(), andValue: dist.value/(elapsed.value/3600.0))
                }else{
                    return nil
                }
            case .GpH:
                if let total = self.stats[.FuelTotalizer]?.sumWithUnit.convert(to: GCUnit.usgallon()),
                   let elapsed = self.stats[.Moving]?.sumWithUnit.convert(to: GCUnit.second()) {
                    return GCNumberWithUnit(unit: GCUnit.gph(), andValue: total.value/(elapsed.value/3600.0))
                }else{
                    return nil
                }
            case .NmpG:
                if let total = self.stats[.FuelTotalizer]?.sumWithUnit.convert(to: GCUnit.usgallon()),
                   let dist = self.stats[.Distance]?.sumWithUnit.convert(to: GCUnit.nm()) {
                    return GCNumberWithUnit(unit: GCUnit.nmpergallon(), andValue: dist.value/total.value)
                }else{
                    return nil
                }
            }
        }
        return nil
    }
    
}


extension Trip : CustomStringConvertible {
    var description: String {
        var strs : [String] = [ "\(self.count) legs" ]
        if let date = self.flightLogFileInfos.last?.start_time {
            strs.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        if let time = self.numberWithUnit(field: .Hobbs) {
            strs.append(time.description)
        }
        if let distance = self.numberWithUnit(field: .Distance) {
            strs.append(distance.description)
        }
        let desc = strs.joined(separator: ", ")
        return "Trip(\(desc))"
    }
}

