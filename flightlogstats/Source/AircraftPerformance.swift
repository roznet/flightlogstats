//
//  Aircraft.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 23/06/2022.
//

import Foundation
import RZUtils

struct AircraftPerformance : Equatable {
    typealias Endurance = TimeInterval
    
    let fuelMax : FuelQuantity
    let fuelTab : FuelQuantity
    
    let gph : Double
        
    init(fuelMax: FuelQuantity, fuelTab: FuelQuantity, gph: Double) {
        self.fuelMax = fuelMax
        self.fuelTab = fuelTab
        self.gph = gph
    }
    
    func endurance(fuel : FuelQuantity) -> Endurance {
        let inGallon = fuel.convert(to: UnitVolume.aviationGallon)
        return (inGallon.total / gph) * 3600.0
    }
    
    static func ==(lhs: AircraftPerformance, rhs: AircraftPerformance) -> Bool {
        return lhs.fuelMax == rhs.fuelMax && lhs.fuelTab == rhs.fuelTab && lhs.gph == rhs.gph
    }
}
