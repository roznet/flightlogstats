//
//  FlightSavvyRecord.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 05/02/2023.
//

import Foundation
import CoreData

class FlightSavvyRecord : NSManagedObject {
    typealias Status = RemoteServiceRecord.Status
    
    
    var status : Status {
        get {
            if let raw = self.upload_status,
                let val = Status(rawValue: raw) {
                return val
            }else{
                return .ready
            }
        }
        set {
            self.upload_status = newValue.rawValue
        }
    }
}
