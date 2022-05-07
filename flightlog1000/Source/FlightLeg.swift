//
//  FlightLeg.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 07/05/2022.
//

import Foundation
import CoreLocation

struct FlightLeg {
    let waypoint_to : Waypoint
    let waypoint_from : Waypoint?
    
    let start_time : Date
    let end_time : Date
    
    let log_data_start : [FlightLogFile.Field:Double]
    let log_data_end   : [FlightLogFile.Field:Double]
    let log_data_avg   : [FlightLogFile.Field:Double]
    let log_data_cum   : [FlightLogFile.Field:Double]
    
}
