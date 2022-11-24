//
//  ValueStats.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 07/05/2022.
//

import Foundation
import RZUtils

public struct ValueStats {
    enum Metric : Hashable{
        case start,end
        case min,max,average
        case total
    }

    private(set) var unit : GCUnit
    
    private(set) var start : Double
    private(set) var end   : Double
    
    private(set) var sum : Double
    private(set) var weightedSum : Double
    private(set) var max : Double
    private(set) var min : Double
    
    private(set) var count : Int
    private(set) var weight : Double

    var isValid : Bool { return self.count != 0 }
    
    static let invalid = ValueStats(value: .nan)

    //MARK: - Access
    var startWithUnit : GCNumberWithUnit { return GCNumberWithUnit(unit: unit, andValue: start) }
    var endWithUnit  : GCNumberWithUnit { return GCNumberWithUnit(unit: unit, andValue: end) }
    
    var sumWithUnit : GCNumberWithUnit { return GCNumberWithUnit(unit: unit, andValue: sum) }
    var weightedSumWithUnit : GCNumberWithUnit { return GCNumberWithUnit(unit: unit, andValue: weightedSum) }
    var maxWithUnit : GCNumberWithUnit { return GCNumberWithUnit(unit: unit, andValue: max) }
    var minWithUnit : GCNumberWithUnit { return GCNumberWithUnit(unit: unit, andValue: min) }

    var averageWithUnit : GCNumberWithUnit { return GCNumberWithUnit(unit: unit, andValue: average) }
    var weighterdAverageWithUnit : GCNumberWithUnit { return GCNumberWithUnit(unit: unit, andValue: weightedAverage) }
    var totalWithUnit : GCNumberWithUnit { return GCNumberWithUnit(unit: unit, andValue: total) }

    var average : Double { return self.sum / Double(self.count) }
    var weightedAverage : Double { return self.weightedSum / self.weight }
    var total : Double { return self.end - self.start}
    
    //MARK: - Create
    init(value : Double, weight : Double = 1.0, unit : GCUnit? = nil) {
        self.start = value
        self.end = value
        self.sum = value
        self.max = value
        self.min = value
        self.count = value.isFinite ? 1 : 0
        self.weight = weight
        self.weightedSum = value * weight
        self.unit = unit ?? GCUnit.dimensionless()
    }
    
    init(numberWithUnit : GCNumberWithUnit, weight : Double = 1.0) {
        self.init(value: numberWithUnit.value,weight: weight, unit: numberWithUnit.unit)
    }

    //MARK: - update
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
    
    //MARK: Metrics
    func value(for metric: Metric) -> Double{
        switch metric {
        case .max:
            return self.max
        case .average:
            return self.average
        case .min:
            return self.min
        case .end:
            return self.end
        case .start:
            return self.start
        case .total:
            return self.total
        }
    }
    
    func numberWithUnit(for metric : Metric) -> GCNumberWithUnit {
        return GCNumberWithUnit(unit: self.unit, andValue: self.value(for: metric))
    }

}
