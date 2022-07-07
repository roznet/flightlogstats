//
//  FieldCalculations.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 20/06/2022.
//

import Foundation

struct FieldCalculation {
    typealias Field = FlightLogFile.Field
    let output : Field
    let inputs : [Field]
    let initial : Double
    let calcFunc : ([Double]) -> Double
    
    init(output : Field, inputs: [Field], initial : Double = 0.0, calcFunc : @escaping ([Double])->Double){
        self.output = output
        self.inputs = inputs
        self.calcFunc = calcFunc
        self.initial = initial
    }
    
    func evaluate(line : [Double], fieldsMap : [Field:Int], previousLine : [Double]?) -> Double{
        var doubles : [Double] = []
        for field in self.inputs {
            if field == self.output {
                if let previousLine = previousLine {
                    if let idx = fieldsMap[field],
                       let val = previousLine[safe: idx],
                       val.isFinite {
                        doubles.append(val)
                    }else{
                        return .nan
                    }
                }else{
                    doubles.append(self.initial)
                }
            }else{
                if let idx = fieldsMap[field],
                   let val = line[safe: idx],
                   val.isFinite {
                    doubles.append(val)
                }else{
                    return .nan
                }
            }
        }
        return self.calcFunc(doubles)
    }
    static var calculatedFields : [FieldCalculation] = [
        FieldCalculation(output: .FQtyT, inputs: [.FQtyL,.FQtyR]) {
            x in
            return x.reduce(0, +)
        },
        FieldCalculation(output: .WndCross, inputs: [.WndDr,.WndSpd,.CRS]){
            x in
            let dir = x[0] < 0 ? 360.0 + x[0] : x[0]
            var diff = abs(dir - x[2])
            if diff > 180 {
                diff = 360-diff
            }
            let component = __sinpi(diff/180.0)
            return x[1] * component
        },
        FieldCalculation(output: .WndDirect, inputs: [.WndDr,.WndSpd,.CRS]){
            x in
            let dir = x[0] < 0 ? 360.0 + x[0] : x[0]
            var diff = abs(dir - x[2])
            if diff > 180 {
                diff = 360-diff
            }
            let component = __cospi(diff/180.0) * -1.0
            return x[1] * component
        },
        FieldCalculation(output: .FTotalizerT, inputs: [.FTotalizerT,.E1_FFlow]){
            x in
            return x[0] + (x[1]/3600.0)
        }
    ]
}

struct FieldCategorisation {
    typealias Field = FlightLogFile.Field
    let output : Field
    let inputs : [Field]
    let calcFunc : ([[Double]]) -> String
    let rollingCount : Int
    
    init(output : Field, inputs: [Field], rollingCount : Int = 10, calcFunc : @escaping ([[Double]])->String){
        self.output = output
        self.inputs = inputs
        self.rollingCount = rollingCount
        self.calcFunc = calcFunc
    }
    
    func evaluate(values : [Field:[Double]], fieldsMap : [Field:Int]) -> String{
        var doubles : [[Double]] = []
        for field in self.inputs {
            if let val = values[field]{
                doubles.append(val)
            }else{
                return ""
            }
        }
        return self.calcFunc(doubles)
    }
    static var categoryFields : [FieldCategorisation] = [
    ]

}
