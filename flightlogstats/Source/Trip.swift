//
//  Trip.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 04/08/2022.
//

import Foundation
import RZFlight
import RZUtils
import RZData
import RZUtilsSwift

struct Trip {
    typealias Field = FlightSummary.Field
    /// infos in the trips sorted from newest to oldest
    var flightLogFileInfos : [FlightLogFileRecord] = []
    var count : Int { return self.flightLogFileInfos.count }
    var stats : [Field:ValueStats] = [:]
    
    var empty : Bool { return self.flightLogFileInfos.count == 0 }
    
    enum Aggregation {
        case awayFromBase(Airport)
        case calendarUnit(GCStatsDateBuckets)
        case list
    }
    
    var label : String
    
    private let aggregation : Aggregation
    
    init(base: Airport) {
        self.aggregation = .awayFromBase(base)
        self.label = "Trip"
    }
    
    init(flightRecords : [FlightLogFileRecord], label : String) {
        self.label = label
        self.aggregation = .list
        for record in flightRecords {
            self.add(info: record)
        }
    }
    
    init(unit : NSCalendar.Unit, referenceDate : Date? = nil){
        let bucket = GCStatsDateBuckets(for: unit, referenceDate: referenceDate, andCalendar: Calendar.current)
        self.init(bucket: bucket)
    }
    
    private init(bucket : GCStatsDateBuckets) {
        self.aggregation = .calendarUnit(bucket)
        self.label = bucket.description
    }
    
    var startingFlight : FlightLogFileRecord? { return self.flightLogFileInfos.last }
    var endingFlight : FlightLogFileRecord? { return self.flightLogFileInfos.first }
    
    func isNewer(than other: Trip) -> Bool {
        guard let otherstart = other.startingFlight else { return false }
        return self.startingFlight?.isNewer(than: otherstart) ?? false
    }
    
    func isOlder(than other: Trip) -> Bool {
        guard let otherstart = other.startingFlight else { return false }
        return self.startingFlight?.isOlder(than: otherstart) ?? false
    }
    
    mutating func add(info : FlightLogFileRecord) {
        if let summary = info.flightSummary {
            for field in FlightSummary.Field.allCases {
                if let nu = summary.measurement(for: field) {
                    if stats[field] == nil {
                        stats[field] = ValueStats(measurement: nu)
                    }else{
                        stats[field]?.update(measurement: nu)
                    }
                }
            }

            self.flightLogFileInfos.append(info)
            self.flightLogFileInfos.sort {
                $0.isNewer(than: $1)
            }
        }
    }
    
    private mutating func check(base : Airport, info : FlightLogFileRecord) -> CheckStatus {
        
        var rv : CheckStatus = .sameTrip
        if let summary = info.flightSummary,
           let startAirport = summary.startAirport,
           let endAirport = summary.endAirport{
            
            if let last = self.endingFlight {
                guard last.isSameAircraft(as: info) else { return .ignore }
                
                // special case, local flight should be new trip
                if let lastStart = last.flightSummary?.startAirport,
                   let lastEnd = last.flightSummary?.endAirport {
                    // this is a local flight but last one wasn't, start new trip
                    if lastStart == lastEnd && lastStart == base {
                        if startAirport != endAirport  {
                            rv = .startsTrip
                        }
                    }
                }
                
                if last.isNewer(than: info) && startAirport == base{
                    rv = .endsTrip
                }
                if !last.isNewer(than: info) && endAirport == base {
                    rv = .endsTrip
                }
            }
        }
        return rv
    }
    
    
    private mutating func check(bucket : GCStatsDateBuckets, info : FlightLogFileRecord) -> CheckStatus {
        var rv : CheckStatus = .sameTrip
        if let summary = info.flightSummary,
           let start = summary.hobbs?.start {
            if bucket.contains(start) {
                rv = .sameTrip
            }else{
                rv = .startsTrip
            }
        }
        
        return rv
    }
    
    enum CheckStatus {
        case sameTrip
        case startsTrip
        case endsTrip
        case ignore
    }
    
    /// Add the info to the trip
    /// - Parameter info: info to add
    /// - Parameter sample: sample of info in the trip to see if compatible
    /// - Returns: true if this info concludes the trip
    mutating func check(info : FlightLogFileRecord, sample : FlightLogFileRecord? = nil) -> CheckStatus {
        switch aggregation {
        case .awayFromBase(let base):
            if let sample = sample, !sample.isSameAircraft(as: info) {
                return .ignore
            }
            return self.check(base: base, info: info)
        case .calendarUnit(let bucket):
            return self.check(bucket: bucket, info: info)
        case .list:
            return .sameTrip
        }
    }

    func new(info: FlightLogFileRecord? = nil) -> Trip? {
        switch self.aggregation {
        case .awayFromBase(let base):
            return Trip(base: base)
        case .calendarUnit(let bucket):
            if let summary = info?.flightSummary,
               let start = summary.hobbs?.start {
                bucket.bucket(start)
                return Trip(bucket: bucket)
            }
            return Trip(unit: bucket.calendarUnit, referenceDate: bucket.refOrNil)
        case .list:
            return nil
        }
    }
    
    func measurement(field : Field) -> Measurement<Dimension>? {
        if let stats = self.stats[field] {
            switch field {
            case .FuelStart:
                for flight in self.flightLogFileInfos.reversed() {
                    if let summary = flight.flightSummary {
                        return summary.measurement(for: .FuelStart)
                    }
                }
                return nil
            case .FuelEnd:
                for flight in self.flightLogFileInfos {
                    if let summary = flight.flightSummary {
                        return summary.measurement(for: .FuelEnd)
                    }
                }
                return nil
            case .FuelUsed,.FuelTotalizer:
                return stats.sumMeasurement
            case .Distance:
                return stats.sumMeasurement
            case .Altitude:
                return stats.maxMeasurement
            case .Hobbs,.Flying,.Moving:
                return stats.sumMeasurement
            case .GroundSpeed:
                if let dist = self.stats[.Distance]?.sumMeasurement?.converted(to: UnitLength.nauticalMiles),
                   let flying = self.stats[.Flying]?.sumMeasurement?.converted(to: UnitDuration.seconds),
                   let moving = self.stats[.Moving]?.sumMeasurement?.converted(to: UnitDuration.seconds) {
                    var elapsed = flying
                    
                    let nonflying = moving - flying
                    if nonflying > flying {
                        elapsed = moving
                    }
                    return Measurement(value: dist.value/(elapsed.value/3600.0), unit: UnitSpeed.knots)
                }else{
                    return nil
                }
            case .GpH:
                if let total = self.stats[.FuelTotalizer]?.sumMeasurement?.converted(to: UnitVolume.aviationGallon),
                   let elapsed = self.stats[.Moving]?.sumMeasurement?.converted(to: UnitDuration.seconds) {
                    return Measurement(value: total.value/(elapsed.value/3600.0), unit: UnitFuelFlow.gallonPerHour)
                }else{
                    return nil
                }
            case .NmpG:
                if let total = self.stats[.FuelTotalizer]?.sumMeasurement?.converted(to: UnitVolume.aviationGallon),
                   let dist = self.stats[.Distance]?.sumMeasurement?.converted(to: UnitVolume.aviationGallon) {
                    return Measurement(value: dist.value/total.value, unit: UnitFuelEfficiency.nauticalMilesPerGallon)
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
        strs.append(contentsOf: self.flightLogFileInfos.compactMap( { $0.start_airport_icao} ).reversed() )
        if let end = self.flightLogFileInfos.first?.end_airport_icao {
            strs.append(end)
        }
            
        if let date = self.flightLogFileInfos.last?.start_time {
            strs.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        if let time = self.measurement(field: .Hobbs) {
            
            strs.append(DisplayContext.enduranceFormatter.string(from: time))
        }
        if let distance = self.measurement(field: .Distance) {
            strs.append(DisplayContext.defaultFormatter.string(from: distance))
        }
        let desc = strs.joined(separator: ", ")
        return "Trip(\(desc))"
    }
}

