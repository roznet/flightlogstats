//
//  FuelAnalysis.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 23/06/2022.
//

import Foundation


class FuelAnalysis {
    
    struct Inputs {
        let targetFuel : FuelQuantity
        let addedfuel : FuelQuantity
    }
    
    typealias Endurance = Aircraft.Endurance
    
    let aircraft : Aircraft
    let currentFuel : FuelQuantity
    let inputs : Inputs
    
    var targetFuel : FuelQuantity {
        let toAdd = (self.inputs.targetFuel - self.currentFuel).rebalancedNegative
        
        return max(min(self.currentFuel+toAdd,self.aircraft.fuelMax),self.currentFuel)
        
    }
    var targetSave : FuelQuantity { return self.aircraft.fuelMax - self.targetFuel }
    var targetAdd  : FuelQuantity { return self.targetFuel - self.currentFuel }
    
    var addedTotal : FuelQuantity  { return max(min(self.currentFuel + self.inputs.addedfuel,self.aircraft.fuelMax),self.currentFuel) }
    var addedFuel : FuelQuantity { return self.addedTotal - self.currentFuel }
    var addedSave : FuelQuantity { return self.aircraft.fuelMax - self.addedTotal }
    
    var currentEndurance : Endurance { return self.aircraft.endurance(fuel: self.currentFuel) }
    var addedTotalEndurance : Endurance { return self.aircraft.endurance(fuel: self.addedTotal ) }
    var targetEndurance : Endurance { return self.aircraft.endurance(fuel: self.targetFuel) }
    
    var addedLostEndurance : Endurance { return self.aircraft.endurance(fuel: self.addedSave) }
    var targetLostEndurance : Endurance { return self.aircraft.endurance(fuel: self.targetSave) }

    init(aircraft : Aircraft, current : FuelQuantity, inputs : Inputs){
        self.aircraft = aircraft
        self.currentFuel = current
        self.inputs = inputs
    }
    
}
