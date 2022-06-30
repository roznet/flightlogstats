//
//  Settings.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 06/05/2022.
//

import Foundation

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
    
    @UserStorage(key: .unit_target_fuel, defaultValue: "usgallon")
    var unitTargetFuel : String
    
    @UserStorage(key: .unit_added_fuel, defaultValue: "liter")
    var unitAddedFuel : String
       
    @UserStorage(key: .added_fuel_left, defaultValue: 5.0)
    var addedFuelLeft : Double

    @UserStorage(key: .added_fuel_right, defaultValue: 5.0)
    var addedFuelRight : Double
    
    @UserStorage(key: .target_fuel, defaultValue: 70.0)
    var targetFuel : Double


}
