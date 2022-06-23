//
//  FuelQuantity.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 07/05/2022.
//

import Foundation
import RZUtils

struct FuelQuantity {
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
        self.unit = GCUnit.usgallon()
    }
    
    init(total: Double, unit : GCUnit = GCUnit.usgallon()){
        self.left = total / 2.0
        self.right = total / 2.0
        self.unit = GCUnit.usgallon()
    }
}

func -(left: FuelQuantity,right:FuelQuantity) -> FuelQuantity{
    return FuelQuantity(left: left.left-right.left, right: left.right-right.right)
}

func +(left: FuelQuantity,right:FuelQuantity) -> FuelQuantity{
    return FuelQuantity(left: left.left+right.left, right: left.right+right.right)
}


extension FuelQuantity {
    func convert(to : GCUnit) -> FuelQuantity{
        if to.canConvert(to: self.unit) {
            return FuelQuantity(left: to.convert(self.left, from: self.unit), right: to.convert(self.right, from: self.unit), unit: to)
        }
        return self
    }
}
