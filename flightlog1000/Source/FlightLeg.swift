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
    
    let waypoint_to : Waypoint
    let waypoint_from : Waypoint?
    
    let timeRange : TimeRange
    
    var data : [Field:ValueStats]
    
}

extension FlightLeg : CustomStringConvertible {
    var description: String {
        let displayContext = DisplayContext()
        let time = displayContext.formatHHMM(timeRange: self.timeRange)
        return String(format: "<FlightLeg %@-%@ %@>", waypoint_from?.name ?? "", waypoint_to.name, time )        
    }
}
