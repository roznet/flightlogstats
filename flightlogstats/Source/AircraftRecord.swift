//
//  Aircraft.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 28/10/2022.
//

import UIKit
import CoreData

class AircraftRecord: NSManagedObject {
    typealias SystemId = AvionicsSystem.SystemId
    typealias AircraftIdentifier = AvionicsSystem.AircraftIdentifier
    
    weak var container : FlightLogOrganizer? = nil
    func saveContext() {
        self.container?.saveContext()
    }

    var systemId : SystemId { return self.system_id ?? "" }
    var aircraftIdentifier : AircraftIdentifier { return self.aircraft_identifier ?? "" }
    var airframeName : String { return self.airframe_name ?? "" }
    
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
            return AircraftPerformance(fuelMax: FuelTanks(total: self.fuel_max, unit: Settings.fuelStoreUnit),
                                       fuelTab: FuelTanks(total: self.fuel_tab, unit: Settings.fuelStoreUnit),
                                       gph: self.gph )
        }
        set {
            self.fuel_max = newValue.fuelMax.converted(to: Settings.fuelStoreUnit).total
            self.fuel_tab = newValue.fuelTab.converted(to: Settings.fuelStoreUnit).total
            self.gph = newValue.gph
        }
    }
    
    var flightRecords : [FlightLogFileRecord] {
        var rv : [FlightLogFileRecord] = []
        if let flights = self.file_records {
            for flight in flights {
                if let record = flight as? FlightLogFileRecord {
                    rv.append(record)
                }
            }
        }
        
        return rv.sorted { $0.isNewer(than: $1) }
    }
    
    var latestFlight : FlightLogFileRecord? {
        return self.flightRecords.last
    }
    
    func contains(_ searchText : String ) -> Bool {
        return self.airframeName.contains(searchText) || self.aircraftIdentifier.contains(searchText)
    }
}
