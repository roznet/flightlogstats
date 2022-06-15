//
//  FlightLeg.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 07/05/2022.
//

import Foundation
import CoreLocation

struct FlightLeg {
    typealias Field = FlightLogFile.Field
    
    enum LegInfo : String {
        case start_time = "Start"
        case end_time = "End"
        case waypoint_from = "From"
        case waypoint_to = "To"
        case route = "Route"
    }
    
    let waypoint_to : Waypoint
    let waypoint_from : Waypoint?
    
    let timeRange : TimeRange
    
    private var data : [Field:ValueStats]
    
    var fields : [Field] { return Array(data.keys).sorted { $0.order < $1.order } }
    
    init(waypoint_to: Waypoint, waypoint_from: Waypoint?, timeRange: TimeRange, data: [Field : ValueStats]) {
        self.waypoint_to = waypoint_to
        self.waypoint_from = waypoint_from
        self.timeRange = timeRange
        self.data = data
    }
    
    func valueStats(field : Field) -> ValueStats? {
        return self.data[field]
    }
    
    func format(which : LegInfo, displayContext :DisplayContext = DisplayContext(), reference : Date? = nil) -> String {
        switch which {
        case .start_time:
            return displayContext.format(date: self.timeRange.start, since: self.timeRange.start, reference: reference)
        case .end_time:
            return displayContext.format(date: self.timeRange.end, since: self.timeRange.start, reference: reference)
        case .route:
            return displayContext.format(waypoint: self.waypoint_to, from: waypoint_from)
        case .waypoint_from:
            if let waypoint_from = waypoint_from {
                return displayContext.format(waypoint: waypoint_from)
            }else{
                return ""
            }
        case .waypoint_to:
            return displayContext.format(waypoint: self.waypoint_to)
        }
    }
}

extension FlightLeg : CustomStringConvertible {
    var description: String {
        let displayContext = DisplayContext()
        let time = displayContext.formatHHMM(timeRange: self.timeRange)
        return String(format: "<FlightLeg %@-%@ %@>", waypoint_from?.name ?? "", waypoint_to.name, time )        
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
