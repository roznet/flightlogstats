//
//  FieldCalculations.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 20/06/2022.
//

import Foundation
import RZUtils
import RZData

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
            if let vals = lines[field]  {
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
        FieldCalculation(outputs: [.E1_EGT_Max,.E1_EGT_Min], inputs: [.E1_EGT1,.E1_EGT2,.E1_EGT3,.E1_EGT4,.E1_EGT5,.E1_EGT6]) {
            x in
            let max : Double = x.max() ?? .nan
            let min : Double = x.min() ?? .nan
            let idx : Int = x.firstIndex(of: max) ?? 0
            
            // idx + 1 to represent egt number
            return [max,min]
            
        },
        FieldCalculation(outputs: [.E1_CHT_Max,.E1_CHT_Min], inputs: [.E1_CHT1,.E1_CHT2,.E1_CHT3,.E1_CHT4,.E1_CHT5,.E1_CHT6]) {
            x in
            let max : Double = x.max() ?? .nan
            let min : Double = x.min() ?? .nan
            let idx : Int = x.firstIndex(of: max) ?? 0
            
            // idx + 1 to represent egt number
            return [max,min]
            
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
            if x[1].isFinite {
                return x[0] + (x[1]/3600.0)
            }else{
                return x[0]
            }
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
        },
        FieldCalculation(stringOutput: .E1_EGT_MaxIdx, multiInputs: [.E1_EGT1,.E1_EGT2,.E1_EGT3,.E1_EGT4,.E1_EGT5,.E1_EGT6], obsCount: 1) {
            x, _ in
            let temps = x.map { $0.last ?? .nan }
            let max : Double = temps.max() ?? .nan
            guard max.isFinite else { return "" }
            let idx : Int = temps.firstIndex(of: max) ?? -1
            
            // idx + 1 to represent egt number
            let rv = idx >= 0 ? "\(idx+1)" : ""
            return rv
        },
        FieldCalculation(stringOutput: .E1_CHT_MaxIdx, multiInputs: [.E1_CHT1,.E1_CHT2,.E1_CHT3,.E1_CHT4,.E1_CHT5,.E1_CHT6], obsCount: 1) {
            x, _ in
            let temps = x.map { $0.last ?? .nan }
            let max : Double = temps.max() ?? .nan
            guard max.isFinite else { return "" }
            let idx : Int = temps.firstIndex(of: max) ?? -1
            
            // idx + 1 to represent cht number
            let rv = idx >= 0 ? "\(idx+1)" : ""
            return rv
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
