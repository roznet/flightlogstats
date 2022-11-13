//
//  FieldCalculations.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 20/06/2022.
//

import Foundation

/*
 * Stats
 *   per minute:
 *      time
 *      distance
 *      long/lat start
 
 *      engine on/off
 *      phase climb/descent/cruise/ground
 *      AltMSL min/max/start/end
 *      AltGPS min/max/start/end
 
 *      fuel used  total
 *      fuel       imbalance
 
 *      TAS/IAS/GS  min/max/avg
 *      fuel flow  min/max/avg
 *      OilT/OilP avg
 *      MAP max/min/avg
 *      RPM max/min/avg
 *      %pwd max/min/avg
 *      OAT min/max/avg
 *      volt1/2  start/end/avg
 *      amp      start/end/avg
 
 *      CHTn max/min/maxI,minI
 *      EGTn max/min/maxI,minI
 *      TITn max/min/maxI,minI
 
 */


struct FieldCalculation {
    typealias Field = FlightLogFile.Field
    typealias FuncTextMulti = ([[Double]], String?) -> String
    
    let outputs : [Field]
    let inputs : [Field]
    let calcType : CalcType
    let requiredObservationCount : Int
    var output : Field { return self.outputs.first ?? .Lcl_Date }
    private let initial : Double
    private let calcFunc : ([Double]) -> Double
    private let calcFuncArray : ([Double]) -> [Double]
    private let calcFuncTextMulti : FuncTextMulti
    
    var inputType : InputType {
        switch self.calcType {
        case .doublesArrayToString:
            return .doublesArray
        case .doublesToDouble,.doublesToDoublesArray:
            return .doubles
        }
    }
    
    var outputType : OutputType {
        switch self.calcType {
        case .doublesToDouble:
            return .double
        case .doublesArrayToString:
            return .string
        case .doublesToDoublesArray:
            return .doubleArray
        }
    }
    
    enum InputType {
        case doubles
        case doublesArray
    }
    
    enum OutputType {
        case double
        case doubleArray
        case string
    }
    
    enum CalcType {
        case doublesToDouble
        case doublesArrayToString
        case doublesToDoublesArray
    }
    
    init(output : Field, inputs: [Field], initial : Double = 0.0, calcFunc : @escaping ([Double])->Double){
        self.outputs = [output]
        self.inputs = inputs
        self.calcFunc = calcFunc
        self.calcFuncTextMulti = { _,_ in return "" }
        self.calcFuncArray = { _ in return [] }
        self.calcType = .doublesToDouble
        self.initial = initial
        self.requiredObservationCount = 1
    }

    init(outputs : [Field], inputs: [Field], initial : Double = 0.0, calcFunc : @escaping ([Double])->[Double]){
        self.outputs = outputs
        self.inputs = inputs
        self.calcFunc = { _ in return .nan}
        self.calcFuncArray = calcFunc
        self.calcFuncTextMulti = { _,_ in return "" }
        self.calcType = .doublesToDoublesArray
        self.initial = initial
        self.requiredObservationCount = 1
    }

    
    init(stringOutput: Field, multiInputs: [Field], obsCount : Int, calcFunc : @escaping FuncTextMulti ){
        self.outputs = [stringOutput]
        self.inputs = multiInputs
        self.calcFuncTextMulti = calcFunc
        self.calcFuncArray = { _ in return [] }
        self.calcFunc = { _ in return .nan }
        self.calcType = .doublesArrayToString
        self.initial = 0.0
        self.requiredObservationCount = obsCount
    }
    
    func evaluateToString(lines : [Field:[Double]], fieldsMap : [Field:Int], previous : String?) -> String {
        guard self.calcType == .doublesArrayToString else { return "" }
        
        var doublesArray : [[Double]] = []
        for field in self.inputs {
            if let vals = lines[field] {
                doublesArray.append(vals)
            }
        }
        return self.calcFuncTextMulti(doublesArray,previous)
    }
    
    private func doublesInput(line: [Double], fieldsMap: [Field:Int], previousLine : [Double]?) -> [Double] {
        var doubles : [Double] = []
        for field in self.inputs {
            if self.outputs.contains(field) {
                if let previousLine = previousLine {
                    if let idx = fieldsMap[field],
                       let val = previousLine[safe: idx],
                       val.isFinite {
                        doubles.append(val)
                    }else{
                        doubles.append(.nan)
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
                    doubles.append(.nan)
                }
            }
        }
        return doubles
    }
    
    func evaluateToArray(line: [Double], fieldsMap : [Field:Int], previousLine : [Double]?) -> [Double] {
        guard self.calcType == .doublesToDoublesArray else { return self.outputs.map { _ in return .nan } }
        
        return self.calcFuncArray(self.doublesInput(line: line, fieldsMap: fieldsMap, previousLine: previousLine))
    }
    
    func evaluate(line : [Double], fieldsMap : [Field:Int], previousLine : [Double]?) -> Double{
        guard self.calcType == .doublesToDouble else { return .nan }
        
        return self.calcFunc(self.doublesInput(line: line, fieldsMap: fieldsMap, previousLine: previousLine))
    }
    static var calculatedFields : [FieldCalculation] = [
        FieldCalculation(output: .FQtyT, inputs: [.FQtyL,.FQtyR]) {
            x in
            return x.reduce(0, +)
        },
        FieldCalculation(outputs: [.E1_EGT_Max,.E1_EGT_Min,.E1_EGT_MaxIdx], inputs: [.E1_EGT1,.E1_EGT2,.E1_EGT3,.E1_EGT4,.E1_EGT5,.E1_EGT6]) {
            x in
            let max : Double = x.max() ?? .nan
            let min : Double = x.min() ?? .nan
            let idx : Int = x.firstIndex(of: max) ?? 0
            
            return [max,min,Double(idx)]
            
        },
        FieldCalculation(output: .E1_EGT_Max, inputs: [.E1_EGT1,.E1_EGT2,.E1_EGT3,.E1_EGT4,.E1_EGT5,.E1_EGT6]) {
            x in
            return x.max() ?? 0.0
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
        },
        FieldCalculation(stringOutput: .FltPhase, multiInputs: [.IAS,.GndSpd,.AltMSL,.AltGPS,.E1_FFlow], obsCount: 20){
            x, previous in
            guard x[0].count >= 15 else { return previous ?? "Ground" }
            
            if let ias = x[0].last,
               let gndspd = x[1].min(),
               let altend = x[2].last,
               let altstart = x[2].first {
                if ias > 35.0 {
                    if altend > altstart + 50 {
                        return "Climb"
                    }else if altend < altstart - 50 {
                        return "Descent"
                    }
                    return "Cruise"
                }else{
                    return "Ground"
                }
            }
            return "Unknown"
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
