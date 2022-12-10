//
//  FlightFuelRecord.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 02/07/2022.
//

import UIKit
import CoreData
import RZUtils

/// Record for the end of a flight
class FlightFuelRecord: NSManagedObject {

    var fuelAnalysisInputs : FuelAnalysis.Inputs {
        get {
            return FuelAnalysis.Inputs(targetFuel: self.targetFuel, addedfuel: self.addedFuel, totalizerStartFuel: self.totalizerStartFuel)
        }
        set {
            self.targetFuel = newValue.targetFuel
            self.addedFuel = newValue.addedfuel
            self.totalizerStartFuel = newValue.totalizerStartFuel
        }
    }
    
    var totalizerStartNotKnown : Bool {
        return self.totalizer_fuel_start == 0.0
    }
    
    var totalizerStartFuel : FuelQuantity {
        get {
            let start = (self.totalizer_fuel_start == 0.0 ? self.target_fuel : self.totalizer_fuel_start)
            return FuelQuantity(total: start, unit: Settings.fuelStoreUnit)
        }
        set {
            let ingallons = newValue.converted(to: Settings.fuelStoreUnit)
            self.totalizer_fuel_start = ingallons.total
        }
    }
    
    var addedFuel : FuelQuantity {
        get { return FuelQuantity(left: self.added_fuel_left, right: self.added_fuel_right, unit: Settings.fuelStoreUnit) }
        set {
            let ingallons = newValue.converted(to: Settings.fuelStoreUnit)
            self.added_fuel_left = ingallons.left
            self.added_fuel_right = ingallons.right
        }
    }

    var targetFuel : FuelQuantity {
        get { return FuelQuantity(total: self.target_fuel, unit: Settings.fuelStoreUnit) }
        set { let ingallons = newValue.converted(to: Settings.fuelStoreUnit); self.target_fuel = ingallons.total }
    }

    func nextTotalizerStart(for used : FuelQuantity) -> FuelQuantity {
        return self.totalizerStartFuel - used + self.addedFuel
    }
    
    /// setup default from settings
    func setupFromSettings() {
        self.targetFuel = Settings.shared.targetFuel
        self.addedFuel = Settings.shared.addedFuel
        self.totalizerStartFuel = Settings.shared.totalizerStartFuel
    }
    
    /// save latest to settings so next new one is same default
    func saveToSettings() {
        Settings.shared.addedFuel = self.addedFuel
        Settings.shared.targetFuel = self.targetFuel
        Settings.shared.totalizerStartFuel = self.totalizerStartFuel
    }
    
}
