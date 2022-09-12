//
//  GCUnit+Logfile.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 10/05/2022.
//

import Foundation
import RZUtils

extension GCUnit {
    static let mapping : [String:GCUnit] = [
        "%" : GCUnit(forKey: "percentdecimal")!,
        "G" : GCUnit(forKey: "dimensionless")!,
        "Hg" : GCUnit(forKey: "inHg")!, // manifold pressure
        "MHz" : GCUnit(forKey: "MHz")!, // radio frequency
        "amps" : GCUnit(forKey: "dimensionless")!,
        "bool" : GCUnit(forKey: "dimensionless")!,
        "deg" : GCUnit(forKey: "dimensionless")!, // headings degree
        "deg C" : GCUnit(forKey: "celsius")!,
        "deg F" : GCUnit(forKey: "fahrenheit")!,
        "degrees" : GCUnit(forKey: "dimensionless")!, // headings degree
        "enum" : GCUnit(forKey: "dimensionless")!,
        "fpm" : GCUnit(forKey: "feetperminute")!,
        "fsd" : GCUnit(forKey: "dimensionless")!,  // track offset (HCDI/VCDI)
        "ft" : GCUnit(forKey: "footelevation")!,
        "ft lbs" : GCUnit(forKey: "dimensionless")!, // torque
        "ft msl" : GCUnit(forKey: "footelevation")!,
        "ft wgs" : GCUnit(forKey: "footelevation")!,
        "gals" : GCUnit(forKey: "usgallon")!,
        "gph" : GCUnit(forKey: "gph")!,
        "inch" : GCUnit(forKey: "inHg")!, // alt setting
        "kt" : GCUnit(forKey: "knot")!,
        "mt" : GCUnit(forKey: "dimensionless")!,
        "nm" : GCUnit(forKey: "nm")!,
        "psi" : GCUnit(forKey: "psi")!, // oil pressure
        "rpm" : GCUnit(forKey: "dimensionless")!,
        "volts" : GCUnit(forKey: "dimensionless")!,
    ]
    
    static func from(logFileUnit : String) -> GCUnit {
        if let found = Self.mapping[logFileUnit] {
            return found
        }
        return GCUnit(forKey: "dimensionless")!
    }
}
