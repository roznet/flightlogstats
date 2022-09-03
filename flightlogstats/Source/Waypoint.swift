//
//  Waypoint.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 07/05/2022.
//

import Foundation

struct Waypoint : Equatable, Codable {
    let name : String
    
    init?(name : String?) {
        if let name = name {
            self.name = name
        }else{
            return nil
        }
    }
    
}


