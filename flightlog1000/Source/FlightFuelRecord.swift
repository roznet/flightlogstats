//
//  FlightFuelRecord.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 02/07/2022.
//

import UIKit
import CoreData
import RZUtils

class FlightFuelRecord: NSManagedObject {

    var fuelAnalysisInputs : FuelAnalysis.Inputs {
        get {
            return FuelAnalysis.Inputs(targetFuel: self.targetFuel, addedfuel: self.addedFuel)
        }
        set {
            self.targetFuel = newValue.targetFuel
            self.addedFuel = newValue.addedfuel
        }
    }
    
    var addedFuel : FuelQuantity {
        get { return FuelQuantity(left: self.added_fuel_left, right: self.added_fuel_right, unit: Settings.fuelStoreUnit) }
        set {
            let ingallons = newValue.convert(to: Settings.fuelStoreUnit)
            self.added_fuel_left = ingallons.left
            self.added_fuel_right = ingallons.right
        }
    }

    var targetFuel : FuelQuantity {
        get { return FuelQuantity(total: self.target_fuel, unit: Settings.fuelStoreUnit) }
        set { let ingallons = newValue.convert(to: Settings.fuelStoreUnit); self.target_fuel = ingallons.total }
    }

    var totalizerUsed : FuelQuantity {
        get { return FuelQuantity(total: self.totalizer_fuel_used, unit: Settings.fuelStoreUnit) }
        set { let ingallons = newValue.convert(to: Settings.fuelStoreUnit); self.totalizer_fuel_used = ingallons.total }
    }

    /// setup default from settings
    func setupFromSettings() {
        self.targetFuel = Settings.shared.targetFuel
        self.addedFuel = Settings.shared.addedFuel
    }
    
    /// save latest to settings so next new one is same default
    func saveToSettings() {
        Settings.shared.addedFuel = self.addedFuel
        Settings.shared.targetFuel = self.targetFuel
    }
    
}
