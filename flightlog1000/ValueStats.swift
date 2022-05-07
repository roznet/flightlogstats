//
//  ValueStats.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 07/05/2022.
//

import Foundation

public struct ValueStats {
    let start : Double
    private(set) var end   : Double
    
    private(set) var sum : Double
    private(set) var weightedSum : Double
    private(set) var max : Double
    private(set) var min : Double
    
    private(set) var count : Int
    private(set) var weight : Double
    
    var average : Double { return self.sum / Double(self.count) }
    var weightedAverage : Double { return self.weightedSum / self.weight }

    init(value : Double, weight : Double = 1.0) {
        self.start = value
        self.end = value
        self.sum = value
        self.max = value
        self.min = value
        self.count = 1
        self.weight = weight
        self.weightedSum = value * weight
    }
    
    mutating func update(with value : Double, weight : Double = 1) {
        self.end = value
        self.sum += value
        self.max = Swift.max(self.max,value)
        self.min = Swift.min(self.min,value)
        self.count += 1
        self.weight += weight
    }
}
