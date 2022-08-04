//
//  ValueStats.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 07/05/2022.
//

import Foundation
import RZUtils

public struct ValueStats {
    private(set) var unit : GCUnit
    
    private(set) var start : Double
    private(set) var end   : Double
    
    private(set) var sum : Double
    private(set) var weightedSum : Double
    private(set) var max : Double
    private(set) var min : Double
    
    private(set) var count : Int
    private(set) var weight : Double
    
    var average : Double { return self.sum / Double(self.count) }
    var weightedAverage : Double { return self.weightedSum / self.weight }

    var isValid : Bool { return self.count != 0 }
    
    static let invalid = ValueStats(value: .nan)
    
    init(value : Double, weight : Double = 1.0, unit : GCUnit = GCUnit.dimensionless()) {
        self.start = value
        self.end = value
        self.sum = value
        self.max = value
        self.min = value
        self.count = value.isFinite ? 1 : 0
        self.weight = weight
        self.weightedSum = value * weight
        self.unit = unit
    }
    
    init(numberWithUnit : GCNumberWithUnit, weight : Double = 1.0) {
        self.init(value: numberWithUnit.value,weight: weight, unit: numberWithUnit.unit)
    }
    
    mutating func update(numberWithUnit : GCNumberWithUnit, weight : Double = 1){
        let nu = numberWithUnit.convert(to: self.unit)
        self.update(double: nu.value, weight: weight)
    }
    
    mutating func update(double value : Double, weight : Double = 1) {
        // if we got initial value correct
        if self.start.isFinite {
            if value.isFinite {
                self.end = value
                self.sum += value
                self.max = Swift.max(self.max,value)
                self.min = Swift.min(self.min,value)
                self.count += 1
                self.weight += weight
            }
        }else{
            self.start = value
            self.end = value
            self.sum = value
            self.max = value
            self.min = value
            self.count = value.isFinite ? 1 : 0
            self.weight = weight
            self.weightedSum = value * weight
        }
    }
}
