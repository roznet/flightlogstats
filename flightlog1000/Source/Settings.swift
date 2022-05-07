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
    init(key : String, defaultValue : Type){
        self.key = key
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

    init(key : String, defaultValue : Type){
        self.key = key
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
    }
    
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.open_file_mode.rawValue  : Self.defaultOpenFileMode.rawValue,
        ])
    }
        
    @EnumStorage(key: Key.open_file_mode.rawValue, defaultValue: Self.defaultOpenFileMode)
    var openFileMode : OpenFileMode
    
    
        

}
