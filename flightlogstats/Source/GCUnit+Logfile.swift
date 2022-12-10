//
//  GCUnit+Logfile.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 10/05/2022.
//

import Foundation
import RZUtils
import RZUtilsSwift

extension Dimension {
    static func from(logFileUnit : String) -> Dimension {
        switch logFileUnit {
        case "%" : return UnitPercent.percentPerOne
        case "G" : return UnitAcceleration.gravity
        case "Hg" : return UnitPressure.inchesOfMercury // manifold pressure
        case "MHz" : return UnitFrequency.megahertz // radio frequency
        case "amps" : return UnitElectricCurrent.amperes
        case "bool" : return UnitDimensionLess.scalar
        case "deg" : return UnitAngle.degrees // headings degree
        case "deg C" : return UnitTemperature.celsius
        case "deg F" : return UnitTemperature.fahrenheit
        case "degrees" : return UnitAngle.degrees // headings degree
        case "enum" : return UnitDimensionLess.scalar
        case "fpm" : return UnitSpeed.feetPerMinute
        case "fsd" : return UnitAngle.degrees  // track offset (HCDI/VCDI)
        case "ft" : return UnitLength.feet
        case "ft lbs" : return UnitEnergy.footPound // torque
        case "ft msl" : return UnitLength.feet
        case "ft Baro" : return UnitLength.feet
        case "ft wgs" : return UnitLength.feet
        case "gals" : return UnitVolume.aviationGallon
        case "gph" : return UnitFuelFlow.gallonPerHour
        case "inch" : return UnitPressure.inchesOfMercury // alt setting
        case "kt" : return UnitSpeed.knots
        case "mt" : return UnitDimensionLess.scalar
        case "nm" : return UnitLength.nauticalMiles
        case "psi" : return UnitPressure.poundsForcePerSquareInch // oil pressure
        case "rpm" : return UnitAngularVelocity.revolutionsPerMinute
        case "volts" : return UnitElectricPotentialDifference.volts
        default: return UnitDimensionLess.scalar
        }
    }
}

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
