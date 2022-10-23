//
//  File.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 23/10/2022.
//

import Foundation

extension Notification.Name {
    static let ErrorOccured = Notification.Name("ErrorOccured")
}


class ErrorManager {
    var errors : [Error] = []
    
    var hasError : Bool { return !errors.isEmpty }
    
    func popLast() -> Error? {
        return errors.popLast()
    }
    
    func append(error : Error){
        errors.append(error)
        NotificationCenter.default.post(name: .ErrorOccured, object: self)
    }
}
