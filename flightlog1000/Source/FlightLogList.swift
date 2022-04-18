//
//  FlightLogList.swift
//  connectflight
//
//  Created by Brice Rosenzweig on 27/06/2021.
//

import Foundation
import RZUtils
import RZUtilsSwift

class FlightLogList {
    var flightLogs : [FlightLog]
    
    var description : String {
        return "<FlightLogList:\(flightLogs.count)>"
    }
        
    init(logs : [FlightLog] ) {
        self.flightLogs = logs
    }

}
