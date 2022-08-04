//
//  FlightSummary+Field.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 24/07/2022.
//

import Foundation
import RZUtils

extension FlightSummary {
    enum Field : String, CaseIterable {
        case FuelStart
        case FuelEnd
        case FuelUsed
        case FuelTotalizer
        
        case GpH
        case NmpG
        
        case Distance
        case GroundSpeed
        
        case Hobbs
        case Flying
        case Moving
        
    }
    
    func numberWithUnit(for field : Field) -> GCNumberWithUnit? {
        switch field {
        case .Distance:
            return GCNumberWithUnit(unit: GCUnit.nm(), andValue: self.distance)
        case .GroundSpeed:
            if let flying = self.flying?.elapsed {
                return GCNumberWithUnit(unit: GCUnit.knot(), andValue: self.distance/(flying/3600.0))
            }else{
                return GCNumberWithUnit(unit: GCUnit.knot(), andValue: 0.0)
            }
            
            
        case .FuelStart:
            return self.fuelStart.totalWithUnit
        case .FuelEnd:
            return self.fuelEnd.totalWithUnit
        case .FuelUsed:
            return self.fuelUsed.totalWithUnit
        case .FuelTotalizer:
            return self.fuelTotalizer.totalWithUnit
            
        case .GpH:
            if let flying = self.flying?.elapsed {
                let fuelTotal = (self.fuelTotalizer.total > 0.0 ? self.fuelTotalizer.total : self.fuelUsed.total)
                return GCNumberWithUnit(unit: GCUnit.gph(), andValue: fuelTotal / (flying/3600.0))
            }else{
                return GCNumberWithUnit(unit: GCUnit.gph(), andValue: 0.0)
            }
        case .NmpG:
            if self.distance > 0.0 {
                let fuelTotal = (self.fuelTotalizer.total > 0.0 ? self.fuelTotalizer.total : self.fuelUsed.total)
                return GCNumberWithUnit(unit: GCUnit.nmpergallon(), andValue: (self.distance) / fuelTotal )
            }else{
                return GCNumberWithUnit(unit: GCUnit.nmpergallon(), andValue: 0.0)
            }

        case .Hobbs:
            return self.hobbs?.numberWithUnit.convert(to: GCUnit.decimalhour())
        case .Moving:
            return self.moving?.numberWithUnit.convert(to: GCUnit.decimalhour())
        case .Flying:
            return self.flying?.numberWithUnit.convert(to: GCUnit.decimalhour())
        }
    }
    
}
