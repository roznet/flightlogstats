//
//  FuelQuantity.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 07/05/2022.
//

import Foundation
import RZUtils
import OSLog

struct FuelQuantity : Comparable {
    static let gallon : Double = 3.785411784
    static let zero = FuelQuantity(left: 0.0, right: 0.0)
    static let kilogramPerLiter = 0.71
    
    let unit : GCUnit
    let left : Double
    let right : Double
    var total : Double { return left + right }
    
    var totalWithUnit : GCNumberWithUnit { return GCNumberWithUnit(unit: self.unit, andValue: left+right) }
    var leftWithUnit : GCNumberWithUnit { return GCNumberWithUnit(unit: self.unit, andValue: left ) }
    var rightWithUnit : GCNumberWithUnit { return GCNumberWithUnit(unit: self.unit, andValue: right ) }
    
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
    
    init(left : Double, right : Double, unit : GCUnit = GCUnit.usgallon()) {
        self.left = left
        self.right = right
        self.unit = unit
    }
    
    init(total: Double, unit : GCUnit = GCUnit.usgallon()){
        self.left = total / 2.0
        self.right = total / 2.0
        self.unit = unit
    }
    
    static func < (lhs : FuelQuantity, rhs : FuelQuantity) -> Bool {
        if lhs.unit.isEqual(to: rhs.unit) {
            return lhs.total < rhs.total
        }else if lhs.unit.canConvert(to: rhs.unit) {
            let converted = rhs.convert(to: lhs.unit)
            return lhs.total < converted.total
        }else{
            Logger.app.warning("Incompatible FuelQuantity units \(lhs.unit), \(rhs.unit)")
            return lhs.total < rhs.total
        }
    }
    
    static func == (lhs : FuelQuantity, rhs : FuelQuantity) -> Bool {
        if lhs.unit.isEqual(to: rhs.unit) {
            return lhs.total == rhs.total
        }else if lhs.unit.canConvert(to: rhs.unit) {
            let converted = rhs.convert(to: lhs.unit)
            return lhs.total == converted.total
        }else{
            Logger.app.warning("Incompatible FuelQuantity units \(lhs.unit), \(rhs.unit)")
            return lhs.total == rhs.total
        }
    }
}

func -(left: FuelQuantity,right:FuelQuantity) -> FuelQuantity{
    if left.unit.isEqual(to: right.unit){
        return FuelQuantity(left: left.left-right.left, right: left.right-right.right, unit: left.unit)
    }else if left.unit.canConvert(to: right.unit) {
        let converted = right.convert(to: left.unit)
        return FuelQuantity(left: left.left-converted.left, right: left.right-converted.right, unit: left.unit)
    }else{
        // do diff anyway
        Logger.app.warning("Incompatible FuelQuantity units \(left.unit), \(right.unit)")
        return FuelQuantity(left: left.left-right.left, right: left.right-right.right, unit: left.unit)
    }
}

func +(left: FuelQuantity,right:FuelQuantity) -> FuelQuantity{
    if left.unit.isEqual(to: right.unit){
        return FuelQuantity(left: left.left+right.left, right: left.right+right.right, unit: left.unit)
    }else if left.unit.canConvert(to: right.unit) {
        let converted = right.convert(to: left.unit)
        return FuelQuantity(left: left.left+converted.left, right: left.right+converted.right, unit: left.unit)
    }else{
        // do diff anyway
        Logger.app.warning("Incompatible FuelQuantity units \(left.unit), \(right.unit)")
        return FuelQuantity(left: left.left+right.left, right: left.right+right.right, unit: left.unit)
    }
}

extension FuelQuantity : CustomStringConvertible {
    var description: String {
        return "FuelQuantity(total: \(self.total) \(self.unit.abbr))"
    }
}

extension FuelQuantity {
    func convert(to : GCUnit) -> FuelQuantity{
        if self.unit.isEqual(to: to) {
            return self
        }
        if to.canConvert(to: self.unit) {
            return FuelQuantity(left: to.convert(self.left, from: self.unit), right: to.convert(self.right, from: self.unit), unit: to)
        }
        return self
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
