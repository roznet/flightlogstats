//
//  CategoricalStats.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 24/11/2022.
//

import Foundation

public struct CategoricalStats<CategoricalValue : Hashable>{
    enum Metric : Hashable{
        case start,end
        case mostFrequent
    }
    
    private var valuesCount : [CategoricalValue:Int]
    private(set) var start : CategoricalValue
    private(set) var end : CategoricalValue
    var mostFrequent : CategoricalValue
    
    init(value: CategoricalValue){
        self.start = value
        self.end = value
        self.mostFrequent = value
        self.valuesCount = [value:1]
    }
    
    mutating func update(value: CategoricalValue) {
        self.end = value
        self.valuesCount[value, default: 0] += 1
        if self.valuesCount[self.mostFrequent, default: 0] < self.valuesCount[value, default: 0] {
            self.mostFrequent = value
        }
    }

    
}
