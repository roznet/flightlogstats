//
//  Visit.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 24/08/2022.
//

import Foundation
import RZFlight
import RZUtils
import OSLog

struct Visit {
    
    let airport : Airport
    
    let arrivingFlight : FlightLogFileInfo
    var departingFlight : FlightLogFileInfo? = nil
    
    var numberOfDays : Int {
        if let arrivingTime = arrivingFlight.flightSummary?.hobbs?.end,
           let departingTime = departingFlight?.flightSummary?.hobbs?.start {
            return Calendar.current.numberOfNights(from: arrivingTime, to: departingTime)
        }
        return 0
    }
    
    mutating func departed(with flight : FlightLogFileInfo){
        self.departingFlight = flight
    }
}
