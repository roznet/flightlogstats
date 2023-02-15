//
//  FlightFlyStoStatus.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 15/10/2022.
//

import Foundation
import CoreData

class FlightFlyStoRecord : NSManagedObject {
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
