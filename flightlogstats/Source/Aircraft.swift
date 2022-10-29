//
//  Aircraft.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 28/10/2022.
//

import UIKit
import CoreData

class Aircraft: NSManagedObject {

    weak var container : FlightLogOrganizer? = nil
    func saveContext() {
        self.container?.saveContext()
    }

    var avionicsSystem : AvionicsSystem? {
        get {
            guard let i = self.aircraft_identifier, let n = self.airframe_name, let s = self.system_id else { return nil }
            return AvionicsSystem(aircraftIdentifier: i, airframeName: n, systemId: s)
        }
        set {
            if let newValue = newValue {
                self.aircraft_identifier = newValue.aircraftIdentifier
                self.airframe_name = newValue.airframeName
                self.system_id = newValue.systemId
            }else{
                self.aircraft_identifier = nil
                self.airframe_name = nil
                self.system_id = nil
            }
        }
    }
    
    var aircraftPerformance : AircraftPerformance {
        get {
            return AircraftPerformance(fuelMax: FuelQuantity(total: self.fuel_max, unit: Settings.fuelStoreUnit),
                                       fuelTab: FuelQuantity(total: self.fuel_tab, unit: Settings.fuelStoreUnit),
                                       gph: self.gph )
        }
        set {
            self.fuel_max = newValue.fuelMax.totalWithUnit.convert(to: Settings.fuelStoreUnit).value
            self.fuel_tab = newValue.fuelTab.totalWithUnit.convert(to: Settings.fuelStoreUnit).value
            self.gph = newValue.gph
        }
    }
}
