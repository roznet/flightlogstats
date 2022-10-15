//
//  FlightFlyStoStatus.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 15/10/2022.
//

import Foundation
import CoreData

class FlightFlyStoStatus : NSManagedObject {
    enum Status : String {
        /// files with status pending should be uploaded when opportunity occurs in background upload
        case pending
        /// ready is default, and nothing should happen automatically, but can be manually uploaded
        case ready
        /// already uploaded, nothing to do
        case uploaded
        /// failed
        case failed
    }

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
