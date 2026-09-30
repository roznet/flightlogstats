//
//  ServiceRecord.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 15/02/2023.
//

import Foundation

class RemoteServiceRecord {
    
    enum Status : String {
        /// queued: uploaded by `UploadCoordinator` when it drains
        case pending
        /// ready is default, and nothing should happen automatically, but can be manually uploaded
        case ready
        /// already uploaded, nothing to do
        case uploaded
        /// failed: retried at `next_retry` if set, else on Retry all
        case failed
        
        var description : String {
            return self.rawValue
        }
    }
    
}
