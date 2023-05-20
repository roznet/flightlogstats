//
//  ServiceRequest.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 15/02/2023.
//

import Foundation

class AsyncOperation : Operation {
    override open var isAsynchronous: Bool {
        return true
    }
    
    private var _isExecuting : Bool = false
    override open private(set) var isExecuting: Bool {
        get {
            return _isExecuting
        }
        set {
            willChangeValue(forKey: "isExecuting")
            _isExecuting = newValue
            didChangeValue(forKey: "isExecuting")
        }
    }
    
    private var _isFinished: Bool = false
    override open private(set) var isFinished: Bool {
        get {
            return _isFinished
        }
        set {
            willChangeValue(forKey: "isFinished")
            _isFinished = newValue
            didChangeValue(forKey: "isFinished")
        }
    }
    
    

}
extension Notification.Name {
    static let newFileUploaded : Notification.Name = Notification.Name("Notification.Name.NewFileUploaded")
}

class RemoteServiceRequest {
    

    var progress : ProgressReport? = nil
    
    typealias CompletionHandler = (Status,RemoteServiceRequest) -> Void
    
    enum Status : Equatable {
        case success
        case already(String)
        case error(String)
        case progressing(Double)
        case tokenExpired
        case denied
        
        var description : String {
            switch self {
            case .success:
                return "Success"
            case .already:
                return "Already"
            case .tokenExpired,.error:
                return "Error"
            case .denied:
                return "Denied"
            case .progressing:
                return "In process"
            }
        }
    }

    
}
