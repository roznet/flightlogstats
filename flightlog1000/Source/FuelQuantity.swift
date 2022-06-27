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




extension FuelQuantity {
    func convert(to : GCUnit) -> FuelQuantity{
        if to.canConvert(to: self.unit) {
            return FuelQuantity(left: to.convert(self.left, from: self.unit), right: to.convert(self.right, from: self.unit), unit: to)
        }
        return self
    }
}
