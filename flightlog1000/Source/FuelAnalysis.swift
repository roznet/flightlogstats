//
//  FuelAnalysis.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 23/06/2022.
//

import Foundation

class FuelAnalysis {
    
    typealias Endurance = Aircraft.Endurance
    
    let aircraft : Aircraft
    let currentFuel : FuelQuantity
    let targetFuel : FuelQuantity
    let addedfuel : FuelQuantity
    
    var targetSave : FuelQuantity { return self.aircraft.fuelMax - self.targetFuel }
    var targetAdd  : FuelQuantity { return self.targetFuel - self.currentFuel }
    
    var addedTotal : FuelQuantity  { return self.currentFuel + self.addedfuel }
    var addedSave : FuelQuantity { return self.aircraft.fuelMax - self.addedTotal }
    
    var currentEndurance : Endurance { return self.aircraft.endurance(fuel: self.currentFuel) }
    var addedTotalEndurance : Endurance { return self.aircraft.endurance(fuel: self.addedTotal ) }
    var targetEndurance : Endurance { return self.aircraft.endurance(fuel: self.targetFuel) }
    
    var addedLostEndurance : Endurance { return self.aircraft.endurance(fuel: self.addedSave) }
    var targetLostEndurance : Endurance { return self.aircraft.endurance(fuel: self.targetSave) }

    init(aircraft : Aircraft, current : FuelQuantity, target : FuelQuantity, added : FuelQuantity){
        self.aircraft = aircraft
        self.currentFuel = current
        self.targetFuel = target
        self.addedfuel = added
    }
    
}
