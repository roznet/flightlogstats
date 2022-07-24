//
//  FlightSummary+Field.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 24/07/2022.
//

import Foundation
import RZUtils

extension FlightSummary {
    enum Field : String {
        case FuelStart
        case FuelEnd
        case FuelUsed
        case FuelTotalizer
        
        case Distance
        
        case Hobbs
        case Flying
        case Moving
        
    }
    
    func numberWithUnit(for field : Field) -> GCNumberWithUnit? {
        switch field {
        case .Distance:
            return GCNumberWithUnit(unit: GCUnit.nm(), andValue: self.distance)
        case .Flying:
            return self.flying?.numberWithUnit
        case .FuelStart:
            return self.fuelStart.totalWithUnit
        case .FuelEnd:
            return self.fuelEnd.totalWithUnit
        case .FuelTotalizer:
            return self.fuelTotalizer.totalWithUnit
        case .Hobbs:
            return self.hobbs?.numberWithUnit
        case .Moving:
            return self.moving?.numberWithUnit
        case .FuelUsed:
            return self.fuelUsed.totalWithUnit
        }
    }
    
}
