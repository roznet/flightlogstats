//
//  Trip.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 04/08/2022.
//

import Foundation
import RZFlight
import RZUtils

struct Trip {
    typealias Field = FlightSummary.Field
    /// infos in the trips sorted from newest to oldest
    var flightLogFileInfos : [FlightLogFileInfo] = []
    var count : Int { return self.flightLogFileInfos.count }
    var stats : [Field:ValueStats] = [:]
    
    let base : Airport
    
    init( base: Airport) {
        self.base = base
    }
    
    /// Add the info to the trip
    /// - Parameter info: info to add
    /// - Returns: true if this info concludes the trip
    mutating func add(info : FlightLogFileInfo) -> Bool {
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
            
            for field in FlightSummary.Field.allCases {
                if let nu = summary.numberWithUnit(for: field) {
                    if stats[field] == nil {
                        stats[field] = ValueStats(numberWithUnit: nu)
                    }else{
                        stats[field]?.update(numberWithUnit: nu)
                    }
                }
            }
            
            flightLogFileInfos.append(info)
            flightLogFileInfos.sort {
                $0.isNewer(than: $1)
            }
        }
        return rv
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
            case .Hobbs,.Flying,.Moving:
                return stats.sumWithUnit
            case .GroundSpeed:
                if let dist = self.stats[.Distance]?.sumWithUnit.convert(to: GCUnit.nm()),
                   let elapsed = self.stats[.Flying]?.sumWithUnit.convert(to: GCUnit.second()) {
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

