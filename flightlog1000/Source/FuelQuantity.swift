//
//  FuelQuantity.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 07/05/2022.
//

import Foundation

struct FuelQuantity {
    static let gallon : Double = 3.785411784
    static let zero = FuelQuantity(left: 0.0, right: 0.0)
    
    let left : Double
    let right : Double
    var total : Double { return left + right }
    
    var totalAsGallon : String { return String(format: "%.1f gal", self.total) }
    var totalAsLiter : String { return String(format: "%.1f L", self.total/Self.gallon) }
}

func -(left: FuelQuantity,right:FuelQuantity) -> FuelQuantity{
    return FuelQuantity(left: left.left-right.left, right: left.right-right.right)
}
