//
//  ServiceRecord.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 15/02/2023.
//

import Foundation

class RemoteServiceRecord {
    
    enum Status : String {
        /// files with status pending should be uploaded when opportunity occurs in background upload
        case pending
        /// ready is default, and nothing should happen automatically, but can be manually uploaded
        case ready
        /// already uploaded, nothing to do
        case uploaded
        /// failed
        case failed
        
        var description : String {
            return self.rawValue
        }
    }
    
}
