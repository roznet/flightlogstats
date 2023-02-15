//
//  ServiceRequest.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 15/02/2023.
//

import Foundation

class RemoteServiceRequest {
    
    typealias CompletionHandler = (Status) -> Void
    
    enum Status : Equatable {
        case success
        case already
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
