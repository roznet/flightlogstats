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
    
    let start_time : Date
    let end_time : Date
    
    var data : [Field:ValueStats]
    
}
