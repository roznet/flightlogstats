//
//  FuelQuantity.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 07/05/2022.
//

import Foundation
import RZUtils
import OSLog

struct FuelQuantity : Comparable, Codable {
    static let gallon : Double = 3.785411784
    static let zero = FuelQuantity(left: 0.0, right: 0.0)
    static let kilogramPerLiter = 0.71
    
    let unit : UnitVolume
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
        if let u = GCUnit(forKey: unitkey), let uu = u.foundationUnit as? UnitVolume{
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
    
    var totalMeasurement : Measurement<UnitVolume> { return Measurement(value: self.total, unit: self.unit)}
    var leftMeasurement : Measurement<UnitVolume> { return Measurement(value: self.left, unit: self.unit)}
    var rightMeasurement : Measurement<UnitVolume> { return Measurement(value: self.left, unit: self.unit)}
    
    /// make sure the quantity is positive only, but rebalances if one side is positive the other is negative
    var positiveOnly : FuelQuantity {
        if self.left < 0.0 && self.right > 0.0  {
            return FuelQuantity(left: 0.0, right: max(0.0,self.total), unit: self.unit)
        }
        if self.left > 0.0 && self.right < 0.0  {
            return FuelQuantity(left: max(0.0,self.total), right: 0.0, unit: self.unit)
        }
        return FuelQuantity(left: max(0.0,self.left), right: max(0.0,self.right), unit: self.unit)
    }
    
    init(left : Double, right : Double, unit : UnitVolume = UnitVolume.aviationGallon) {
        self.left = left
        self.right = right
        self.unit = unit
    }
    
    init(left : Measurement<UnitVolume>, right : Measurement<UnitVolume>) {
        self.left = left.value
        self.unit = left.unit
        self.right = right.converted(to: self.unit).value
    }
    
    init(total: Double, unit : UnitVolume = UnitVolume.aviationGallon){
        self.left = total / 2.0
        self.right = total / 2.0
        self.unit = unit
    }
    
    static func < (lhs : FuelQuantity, rhs : FuelQuantity) -> Bool {
        return lhs.totalMeasurement < rhs.totalMeasurement
    }
    
    static func == (lhs : FuelQuantity, rhs : FuelQuantity) -> Bool {
        return lhs.totalMeasurement == rhs.totalMeasurement
    }
}

func -(left: FuelQuantity,right:FuelQuantity) -> FuelQuantity{
    return FuelQuantity(left: left.leftMeasurement - right.leftMeasurement, right: left.rightMeasurement - right.rightMeasurement)
}

func +(left: FuelQuantity,right:FuelQuantity) -> FuelQuantity{
    return FuelQuantity(left: left.leftMeasurement + right.leftMeasurement, right: left.rightMeasurement + right.rightMeasurement)
}

extension FuelQuantity : CustomStringConvertible {
    var description: String {
        let formatter = MeasurementFormatter()
        return "FuelQuantity(total: \(formatter.string(from: self.totalMeasurement))"
    }
}

extension FuelQuantity {
    func convert(to newUnit : UnitVolume) -> FuelQuantity{
        if self.unit == newUnit {
            return self
        }
        let leftconverted = Measurement(value: self.left, unit: self.unit).converted(to: newUnit).value
        let rightconverted = Measurement(value: self.right, unit: self.unit).converted(to: newUnit).value
        return FuelQuantity(left: leftconverted, right: rightconverted, unit: newUnit)
    }
}

func min(_ lhs : FuelQuantity, _ rhs : FuelQuantity) -> FuelQuantity {
    let converted = rhs.convert(to: lhs.unit)
    return FuelQuantity(left: min(lhs.left,converted.left), right: min(lhs.right,converted.right), unit: lhs.unit)
}

func max(_ lhs : FuelQuantity, _ rhs : FuelQuantity) -> FuelQuantity {
    let converted = rhs.convert(to: lhs.unit)
    return FuelQuantity(left: max(lhs.left,converted.left), right: max(lhs.right,converted.right), unit: lhs.unit)
}
