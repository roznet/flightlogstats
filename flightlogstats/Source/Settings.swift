//
//  Settings.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 06/05/2022.
//

import Foundation
import RZUtils
import OAuthSwift
import RZUtilsSwift




struct Settings {
    static let fuelStoreUnit : UnitVolume = UnitVolume.aviationGallon
    
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
    enum ImportMethod : String {
        case automatic
        case fromDate
        case sinceLastImport
        case selectedFile
    }
    enum UploadMethod : String {
        case manual
        case automatic
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
        case totalizer_start_fuel = "totalizer_start_fuel"
        case fuel_config_first_use_acknowledged = "fuel_config_first_use_acknowledged"
        
        case flysto_credentials = "flysto.credentials"
        case flysto_enabled = "flysto.enabled"
        case savvy_token = "savvy.token"
        case savvy_enabled = "savvy.enabled"
        
        case upload_method = "upload.method"
        
        case import_method = "import.method"
        case import_startdate = "import.startdate"
        
        case database_version = "database_version"
    }
    
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.open_file_mode.rawValue  : Self.defaultOpenFileMode.rawValue,
            //Key.unit_added_fuel.rawValue : "liter",
            //Key.unit_target_fuel.rawValue : "usgallon"
        ])
    }

    @UserStorage(key: Key.database_version, defaultValue: 1)
    var databaseVersion : Int
    
    @EnumStorage(key: Key.open_file_mode, defaultValue: Self.defaultOpenFileMode)
    var openFileMode : OpenFileMode
    
    @UnitStorage(key: Key.unit_target_fuel, defaultValue: UnitVolume.aviationGallon)
    var unitTargetFuel : UnitVolume
    
    @UnitStorage(key: Key.unit_added_fuel, defaultValue: UnitVolume.liters)
    var unitAddedFuel : UnitVolume
       
    @UserStorage(key: Key.added_fuel_left, defaultValue: 0.0)
    private var addedFuelLeft : Double

    @UserStorage(key: Key.added_fuel_right, defaultValue: 0.0)
    private var addedFuelRight : Double
    
    @UserStorage(key: Key.target_fuel, defaultValue: 70.0)
    private var targetFuelTotal : Double

    @UserStorage(key: Key.totalizer_start_fuel, defaultValue: 92.0)
    private var totalizerStartFuelTotal : Double

    @UserStorage(key: Key.aircraft_max_fuel, defaultValue: 92.0)
    private var aircraftMaxFuelTotal : Double
    
    @UserStorage(key: Key.aircraft_tab_fuel, defaultValue: 60.0)
    private var aircraftTabFuelTotal : Double

    @UserStorage(key: Key.aircraft_gph, defaultValue: 17.0)
    private var aircraftGph : Double

    @UserStorage(key: Key.fuel_config_first_use_acknowledged, defaultValue: false)
    var fuelConfigFirstUseAcknowledged : Bool
    
    @UserStorage(key: Key.flysto_enabled, defaultValue: false)
    var flystoEnabled : Bool
    @CodableStorage(key: Key.flysto_credentials)
    var flystoCredentials : OAuthSwiftCredential?

    @UserStorage(key: Key.savvy_enabled, defaultValue: false)
    var savvyEnabled : Bool
    @CodableStorage(key: Key.savvy_token)
    var savvyToken : String?
   
    
    @EnumStorage(key: Key.upload_method, defaultValue: .manual)
    var uploadMethod : UploadMethod
    
    //Default on macos is selected file, on iOS automatic
#if targetEnvironment(macCatalyst)
    @EnumStorage(key: Key.import_method, defaultValue: .selectedFile)
    var importMethod : ImportMethod
#else
    @EnumStorage(key: Key.import_method, defaultValue: .automatic)
    var importMethod : ImportMethod
#endif
    

    @UserStorage(key: Key.import_startdate, defaultValue: Date())
    var importStartDate : Date

    var targetFuel : FuelQuantity {
        get { return FuelQuantity(total: self.targetFuelTotal, unit: Settings.fuelStoreUnit ) }
        set { self.targetFuelTotal = newValue.converted(to: Settings.fuelStoreUnit).total }
    }
    var totalizerStartFuel : FuelQuantity {
        get { return FuelQuantity(total: self.totalizerStartFuelTotal, unit: Settings.fuelStoreUnit ) }
        set { self.totalizerStartFuelTotal = newValue.converted(to: Settings.fuelStoreUnit).total }
    }

    var addedFuel : FuelQuantity {
        get { return FuelQuantity(left: self.addedFuelLeft, right: self.addedFuelRight, unit: Settings.fuelStoreUnit ) }
        set {
            let ingallons = newValue.converted(to: Settings.fuelStoreUnit )
            self.addedFuelLeft = ingallons.left
            self.addedFuelRight = ingallons.right
        }
    }
    
    var aircraftPerformance : AircraftPerformance {
        get { return AircraftPerformance(fuelMax: FuelQuantity(total: self.aircraftMaxFuelTotal, unit: Self.fuelStoreUnit),
                              fuelTab: FuelQuantity(total: self.aircraftTabFuelTotal, unit: Self.fuelStoreUnit),
                              gph: self.aircraftGph)}
        set {
            self.aircraftMaxFuelTotal = newValue.fuelMax.total
            self.aircraftTabFuelTotal = newValue.fuelTab.total
            self.aircraftGph = newValue.gph
        }
    }
}

