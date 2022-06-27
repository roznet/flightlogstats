//
//  Aircraft.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 23/06/2022.
//

import Foundation
import RZUtils

struct Aircraft {
    typealias Endurance = TimeInterval
    
    let fuelMax : FuelQuantity
    let fuelTab : FuelQuantity
    
    let gph : Double
    
    //static let default = Aircraft()
    
    init(fuelMax: FuelQuantity, fuelTab: FuelQuantity, gph: Double) {
        self.fuelMax = fuelMax
        self.fuelTab = fuelTab
        self.gph = gph
    }
    
    func endurance(fuel : FuelQuantity) -> Endurance {
        let inGallon = fuel.convert(to: GCUnit.usgallon())
        return (inGallon.total / gph) * 3600.0
    }
}
