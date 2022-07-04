//
//  Settings.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 06/05/2022.
//

import Foundation
import RZUtils

@propertyWrapper
struct UserStorage<Type> {
    private let key : String
    private let defaultValue : Type
    init(key : Settings.Key, defaultValue : Type){
        self.key = key.rawValue
        self.defaultValue = defaultValue
    }
    
    var wrappedValue : Type {
        get {
            UserDefaults.standard.object(forKey: key) as? Type ?? defaultValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}

@propertyWrapper
struct UnitStorage {
    private let key : String
    private let defaultValue : GCUnit
    init(key : Settings.Key, defaultValue : GCUnit){
        self.key = key.rawValue
        self.defaultValue = defaultValue
    }
    
    var wrappedValue : GCUnit {
        get {
            if let key = UserDefaults.standard.object(forKey: key) as? String,
                let unit = GCUnit(forKey: key){
                return unit
            }else{
                return defaultValue
            }
        }
        set {
            UserDefaults.standard.set(newValue.key, forKey: key)
        }
    }
}


@propertyWrapper
struct EnumStorage< Type : RawRepresentable > {
    private let key : String
    private let defaultValue : Type

    init(key : Settings.Key, defaultValue : Type){
        self.key = key.rawValue
        self.defaultValue = defaultValue
    }
    
    var wrappedValue : Type {
        get {
            if let raw = UserDefaults.standard.object(forKey: key) as? Type.RawValue {
                return Type(rawValue: raw) ?? defaultValue
            }else{
                return defaultValue
            }
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }

}


struct Settings {
    static let fuelStoreUnit : GCUnit = GCUnit.usgallon()
    
    static var shared : Settings = Settings()
    
    private init(){}
    
#if targetEnvironment(macCatalyst)
    static let defaultOpenFileMode : OpenFileMode = .csv
#else
    static let defaultOpenFileMode : OpenFileMode = .folder
#endif
    
    enum OpenFileMode : String {
        case folder = "folder"
        case csv = "csv"
    }
    
    enum Key : String {
        case open_file_mode = "open-file-mode"
        case aircraft_max_fuel = "aicraft-max-fuel"
        case aircraft_tab_fuel = "aicraft-tab-fuel"
        case aircraft_gph = "aicraft-gph"
        
        case unit_target_fuel = "unit_target_fuel"
        case unit_added_fuel = "unit_added_fuel"
        
        case target_fuel = "target_fuel"
        case added_fuel_left = "added_fuel_left"
        case added_fuel_right = "added_fuel_right"
    }
    
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.open_file_mode.rawValue  : Self.defaultOpenFileMode.rawValue,
            //Key.unit_added_fuel.rawValue : "liter",
            //Key.unit_target_fuel.rawValue : "usgallon"
        ])
    }
        
    @EnumStorage(key: .open_file_mode, defaultValue: Self.defaultOpenFileMode)
    var openFileMode : OpenFileMode
    
    @UnitStorage(key: .unit_target_fuel, defaultValue: GCUnit.usgallon())
    var unitTargetFuel : GCUnit
    
    @UnitStorage(key: .unit_added_fuel, defaultValue: GCUnit.liter())
    var unitAddedFuel : GCUnit
       
    @UserStorage(key: .added_fuel_left, defaultValue: 5.0)
    private var addedFuelLeft : Double

    @UserStorage(key: .added_fuel_right, defaultValue: 5.0)
    private var addedFuelRight : Double
    
    @UserStorage(key: .target_fuel, defaultValue: 70.0)
    private var targetFuelTotal : Double

    @UserStorage(key: .aircraft_max_fuel, defaultValue: 92.0)
    private var aircraftMaxFuelTotal : Double
    
    @UserStorage(key: .aircraft_tab_fuel, defaultValue: 60.0)
    private var aircraftTabFuelTotal : Double

    @UserStorage(key: .aircraft_gph, defaultValue: 17.0)
    private var aircraftGph : Double

    var targetFuel : FuelQuantity {
        get { return FuelQuantity(total: self.targetFuelTotal, unit: Settings.fuelStoreUnit ) }
        set { self.targetFuelTotal = newValue.convert(to: Settings.fuelStoreUnit).total }
    }
    var addedFuel : FuelQuantity {
        get { return FuelQuantity(left: self.addedFuelLeft, right: self.addedFuelRight, unit: Settings.fuelStoreUnit ) }
        set {
            let ingallons = newValue.convert(to: Settings.fuelStoreUnit )
            self.addedFuelLeft = ingallons.left
            self.addedFuelRight = ingallons.right
        }
    }
    
    var aircraft : Aircraft {
        get { return Aircraft(fuelMax: FuelQuantity(total: self.aircraftMaxFuelTotal, unit: Self.fuelStoreUnit),
                              fuelTab: FuelQuantity(total: self.aircraftTabFuelTotal, unit: Self.fuelStoreUnit),
                              gph: self.aircraftGph)}
        set {
            self.aircraftMaxFuelTotal = newValue.fuelMax.total
            self.aircraftTabFuelTotal = newValue.fuelTab.total
            self.aircraftGph = newValue.gph
        }
    }
}

