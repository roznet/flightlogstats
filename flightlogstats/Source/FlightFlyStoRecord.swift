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

extension FlightLogFileRecord {
    
    var flystoStatus : FlightFlyStoRecord.Status {
        get {
            return self.flysto_record?.status ?? .ready
        }
        set {
            self.ensureFlyStoStatus()
            self.flysto_record?.status = newValue
            self.flysto_record?.status_date = Date()
        }
    }
    var flystoUpdateDate : Date? {
        return self.flysto_record?.status_date
    }
    /// why the last upload failed
    var flystoLastError : String? {
        return self.flysto_record?.last_error
    }
    var flystoReceipt : UploadReceipt? {
        guard let response = self.flysto_record?.upload_response else { return nil }
        return UploadReceipt(response: response)
    }
    var flystoLogFilesInformationAvailable : Bool {
        return FlyStoService.fileId(from: self.flysto_record?.upload_response) != nil
    }
}
