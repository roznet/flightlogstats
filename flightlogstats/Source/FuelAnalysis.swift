//
//  FuelAnalysis.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 23/06/2022.
//

import Foundation


class FuelAnalysis {
    
    struct Inputs : Equatable {
        let targetFuel : FuelQuantity
        let addedfuel : FuelQuantity
        let totalizerStartFuel : FuelQuantity
        
        static func ==(lhs: Inputs, rhs: Inputs) -> Bool {
            return lhs.targetFuel == rhs.targetFuel && lhs.addedfuel == rhs.addedfuel && lhs.totalizerStartFuel == rhs.totalizerStartFuel
        }
        
        @inlinable
        public func isAlmostEqual(
          to other: Self
        ) -> Bool {
            return self.targetFuel.isAlmostEqual(to: other.targetFuel)
            && self.addedfuel.isAlmostEqual(to: other.addedfuel)
            && self.totalizerStartFuel.isAlmostEqual(to: other.totalizerStartFuel)
        }
    }
    
    typealias Endurance = AircraftPerformance.Endurance
    
    let aircraftPerformance : AircraftPerformance
    let currentFuel : FuelQuantity
    let totalizerUsedFuel : FuelQuantity
    let inputs : Inputs
    
    var currentFuelTotalizer : FuelQuantity {
        return (self.inputs.totalizerStartFuel - self.totalizerUsedFuel).positiveOnly
    }
    
    var targetFuel : FuelQuantity {
        let toAdd = (self.inputs.targetFuel - self.currentFuel).positiveOnly
        
        return max(min(self.currentFuel+toAdd,self.aircraftPerformance.fuelMax),self.currentFuel)
    }
    
    var targetSave : FuelQuantity { return self.aircraftPerformance.fuelMax - self.targetFuel }
    var targetSaveMass : FuelMass { return FuelMass(avgas: self.targetSave) }
    
    var targetAdd  : FuelQuantity { return self.targetFuel - self.currentFuel }
    var targetAddTotalizer  : FuelQuantity { return self.targetFuel - self.currentFuelTotalizer }

    var addedTotal : FuelQuantity  { return max(min(self.currentFuel + self.inputs.addedfuel,self.aircraftPerformance.fuelMax),self.currentFuel) }
    var addedFuel : FuelQuantity { return self.addedTotal - self.currentFuel }
    var addedSave : FuelQuantity { return self.aircraftPerformance.fuelMax - self.addedTotal }
    var addedSaveMass : FuelMass { return FuelMass(avgas: self.addedSave) }

    var addedTotalTotalizer : FuelQuantity  { return max(min(self.currentFuelTotalizer + self.inputs.addedfuel,self.aircraftPerformance.fuelMax),self.currentFuelTotalizer) }
    var addedFuelTotalizer : FuelQuantity { return self.addedTotalTotalizer - self.currentFuelTotalizer }
    var addedSaveTotalizer : FuelQuantity { return self.aircraftPerformance.fuelMax - self.addedTotalTotalizer }
    var addedSaveMassTotalizer : FuelMass { return FuelMass(avgas: self.addedSaveTotalizer) }
    
    var currentEndurance : Endurance { return self.aircraftPerformance.endurance(fuel: self.currentFuel) }
    var addedTotalEndurance : Endurance { return self.aircraftPerformance.endurance(fuel: self.addedTotal ) }
    var currentEnduranceTotalizer : Endurance { return self.aircraftPerformance.endurance(fuel: self.currentFuelTotalizer) }
    var addedTotalEnduranceTotalizer : Endurance { return self.aircraftPerformance.endurance(fuel: self.addedTotalTotalizer ) }
    
    var targetEndurance : Endurance { return self.aircraftPerformance.endurance(fuel: self.targetFuel) }
    
    var addedLostEndurance : Endurance { return self.aircraftPerformance.endurance(fuel: self.addedSave) }
    var addedLostEnduranceTotalizer : Endurance { return self.aircraftPerformance.endurance(fuel: self.addedSaveTotalizer) }
    var targetLostEndurance : Endurance { return self.aircraftPerformance.endurance(fuel: self.targetSave) }

    init(aircraftPerformance : AircraftPerformance, current : FuelQuantity, totalizer: FuelQuantity, inputs : Inputs){
        self.aircraftPerformance = aircraftPerformance
        self.currentFuel = current
        self.inputs = inputs
        self.totalizerUsedFuel = totalizer
    }
    
}
