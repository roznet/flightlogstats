//
//  FuelQuantity.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 07/05/2022.
//

import Foundation
import RZUtils
import OSLog

struct FuelTanks<UnitType : Dimension> : Comparable, Codable {
    //static let gallon : Double = 3.785411784
    //static let zero = FuelTanks(left: 0.0, right: 0.0)
    //static let kilogramPerLiter = 0.71
    
    let unit : UnitType
    let left : Double
    let right : Double
    var total : Double { return left + right }
    
    enum FuelQuantityError : Error {
        case invalidUnit
    }
    
    enum CodingKeys : String, CodingKey {
        case unit, left, right
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        left = try values.decode(Double.self, forKey: .left)
        right = try values.decode(Double.self, forKey: .right)
        let unitkey = try values.decode(String.self, forKey: .unit)
        if let u = GCUnit(forKey: unitkey), let uu = u.foundationUnit as? UnitType{
            unit = uu
        }else{
            throw FuelQuantityError.invalidUnit
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(left, forKey: .left)
        try container.encode(right, forKey: .right)
        if let u = unit.gcUnit?.key {
            try container.encode(u, forKey: .unit)
        }else{
            try container.encode(GCUnit.usgallon().key, forKey: .unit)
        }
    }
    
    var totalMeasurement : Measurement<UnitType> { return Measurement(value: self.total, unit: self.unit)}
    var leftMeasurement : Measurement<UnitType> { return Measurement(value: self.left, unit: self.unit)}
    var rightMeasurement : Measurement<UnitType> { return Measurement(value: self.right, unit: self.unit)}
    
    /// make sure the quantity is positive only, but rebalances if one side is positive the other is negative
    var positiveOnly : FuelTanks {
        if self.left < 0.0 && self.right > 0.0  {
            return FuelTanks(left: 0.0, right: max(0.0,self.total), unit: self.unit)
        }
        if self.left > 0.0 && self.right < 0.0  {
            return FuelTanks(left: max(0.0,self.total), right: 0.0, unit: self.unit)
        }
        return FuelTanks(left: max(0.0,self.left), right: max(0.0,self.right), unit: self.unit)
    }
    
    init(left : Double, right : Double, unit : UnitType) {
        self.left = left
        self.right = right
        self.unit = unit
    }
    
    init(left : Measurement<UnitType>, right : Measurement<UnitType>) {
        self.left = left.value
        self.unit = left.unit
        self.right = right.converted(to: self.unit).value
    }
    
    init(total: Double, unit : UnitType){
        self.left = total / 2.0
        self.right = total / 2.0
        self.unit = unit
    }
    
    static func < (lhs : FuelTanks, rhs : FuelTanks) -> Bool {
        return lhs.totalMeasurement < rhs.totalMeasurement
    }
    
    static func == (lhs : FuelTanks, rhs : FuelTanks) -> Bool {
        return lhs.totalMeasurement == rhs.totalMeasurement
    }
}

func -<UnitType>(left: FuelTanks<UnitType>,right:FuelTanks<UnitType>) -> FuelTanks<UnitType>{
    return FuelTanks(left: left.leftMeasurement - right.leftMeasurement, right: left.rightMeasurement - right.rightMeasurement)
}

func +<UnitType>(left: FuelTanks<UnitType>,right:FuelTanks<UnitType>) -> FuelTanks<UnitType>{
    return FuelTanks(left: left.leftMeasurement + right.leftMeasurement, right: left.rightMeasurement + right.rightMeasurement)
}


extension FuelTanks {
    func converted(to newUnit : UnitType) -> FuelTanks{
        if self.unit == newUnit {
            return self
        }
        let leftconverted = Measurement(value: self.left, unit: self.unit).converted(to: newUnit).value
        let rightconverted = Measurement(value: self.right, unit: self.unit).converted(to: newUnit).value
        return FuelTanks(left: leftconverted, right: rightconverted, unit: newUnit)
    }
}

func min<UnitType>(_ lhs : FuelTanks<UnitType>, _ rhs : FuelTanks<UnitType>) -> FuelTanks<UnitType> {
    let converted = rhs.converted(to: lhs.unit)
    return FuelTanks<UnitType>(left: min(lhs.left,converted.left), right: min(lhs.right,converted.right), unit: lhs.unit)
}

func max<UnitType>(_ lhs : FuelTanks<UnitType>, _ rhs : FuelTanks<UnitType>) -> FuelTanks<UnitType> {
    let converted = rhs.converted(to: lhs.unit)
    return FuelTanks(left: max(lhs.left,converted.left), right: max(lhs.right,converted.right), unit: lhs.unit)
}

typealias FuelQuantity = FuelTanks<UnitVolume>

extension FuelQuantity {
    static let zero = FuelTanks(left: 0.0, right: 0.0, unit: Settings.fuelStoreUnit)
    
    init(avgas fuelMass : FuelMass) {
        let inkilograms = fuelMass.converted(to: UnitMass.kilograms)
        self.left = inkilograms.left / FuelMass.avgasKilogramPerLiter
        self.right = inkilograms.right / FuelMass.avgasKilogramPerLiter
        self.unit = UnitVolume.liters
    }
}

typealias FuelMass = FuelTanks<UnitMass>

extension FuelMass {
    static let avgasKilogramPerLiter = 0.71
    
    init(avgas fuelQuantity: FuelQuantity){
        let inLiters = fuelQuantity.converted(to: UnitVolume.liters)
        self.left = inLiters.left * Self.avgasKilogramPerLiter
        self.right = inLiters.right * Self.avgasKilogramPerLiter
        self.unit = UnitMass.kilograms
    }
}

extension FuelTanks : CustomStringConvertible  {
    var description: String {
        let formatter = MeasurementFormatter()
        return "FuelTanks(total: \(formatter.string(from: self.totalMeasurement))"
    }
}


