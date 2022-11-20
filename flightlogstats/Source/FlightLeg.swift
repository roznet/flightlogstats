//
//  FlightLeg.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 07/05/2022.
//

import Foundation
import CoreLocation
import OSLog

struct FlightLeg {
    typealias Field = FlightLogFile.Field
    
    enum LegInfo : String {
        case start_time = "Start"
        case end_time = "End"
        case waypoint = "Waypoint"
        case route = "Route"
    }
    
    let waypoint : Waypoint
    
    let timeRange : TimeRange
    var start : Date { return timeRange.start }
    var end : Date { return timeRange.end }
    
    private var data : [Field:ValueStats]
    
    var fields : [Field] { return Array(data.keys).sorted { $0.order < $1.order } }
    
    init(waypoint: Waypoint, timeRange: TimeRange, data: [Field : ValueStats]) {
        self.waypoint = waypoint
        self.timeRange = timeRange
        self.data = data
    }
    
    func valueStats(field : Field) -> ValueStats? {
        return self.data[field]
    }
    
    func format(which : LegInfo, displayContext : DisplayContext = DisplayContext(), reference : Date? = nil) -> String {
        switch which {
        case .start_time:
            return displayContext.format(time: self.timeRange.start, since: self.timeRange.start, reference: reference)
        case .end_time:
            return displayContext.format(time: self.timeRange.end, since: self.timeRange.start, reference: reference)
        case .route:
            return displayContext.format(waypoint: self.waypoint)
        case .waypoint:
            return displayContext.format(waypoint: waypoint)
        }
    }
    
    static func legs(from data : FlightData,
                     start : Date? = nil,
                     end : Date? = nil,
                     byfield : Field = .AtvWpt) -> [FlightLeg] {
        var rv : [FlightLeg] = []
        let identifiers : IndexedValuesByField<Date,String,Field> = data.datesStrings(for: [byfield], start: start)
        
        do {
            let stats : IndexedValuesByField<Date,ValueStats,Field> = try data.extract(dates: identifiers.indexes, start: start, end : end)
            
            for idx in 0..<identifiers.count {
                if let identifier = identifiers.value(for: byfield, at: idx),
                   let waypoint = Waypoint(name: identifier),
                   var endTime = end ?? identifiers.indexes.last {
                   let startTime = identifiers.indexes[idx]
                    
                    if idx + 1 < identifiers.count {
                        endTime = identifiers.indexes[idx+1]
                    }
                    var validData : [Field:ValueStats] = [:]
                    for (field,val) in stats.fieldValue(at: idx) {
                        if val.isValid {
                            validData[field] = val
                        }
                    }
                    let leg = FlightLeg(waypoint: waypoint,
                                        timeRange: TimeRange(start: startTime, end: endTime),
                                        data: validData)
                    rv.append(leg)
                }

            }
        }catch{
            Logger.app.error("Failed to extract route \(error.localizedDescription)")
        }
        return rv
    }

}

extension FlightLeg : CustomStringConvertible {
    var description: String {
        let displayContext = DisplayContext()
        let time = displayContext.formatHHMM(timeRange: self.timeRange)
        return String(format: "<FlightLeg %@ %@>", waypoint.name, time )
    }
}

extension Array where Element == FlightLeg {
    typealias Field = FlightLogFile.Field

    var valueStatsByField : [Field:[ValueStats]] {
        var rv : [Field:[ValueStats]] = [:]
        
        // first collect and initialize superset of fields
        for element in self {
            for f in element.fields {
                rv[f] = []
            }
        }
        for element in self {
            for f in rv.keys {
                if let v = element.valueStats(field: f) {
                    rv[f]?.append(v)
                }else{
                    rv[f]?.append(ValueStats.invalid)
                }
            }
        }
        
        return rv
    }
    
}

extension FlightLeg.LegInfo : CustomStringConvertible {
    var description : String { return self.rawValue }
}
