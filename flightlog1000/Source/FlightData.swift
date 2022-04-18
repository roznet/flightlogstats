//
//  FlightData.swift
//  connectflight
//
//  Created by Brice Rosenzweig on 29/06/2021.
//

import Foundation

struct FlightData {
    var meta : [String:String] = [:]
    var units : [String] = []
    var fields : [String] = []
    var columnIsDouble : [Bool] = []
    var values : [[Double]] = []
    var string : [[String]] = []
    
    var doubleFields : [String] {
        var rv : [String] = []
        for (field,isDouble) in zip(fields, columnIsDouble) {
            if isDouble {
                rv.append(field)
            }
        }
        return rv
    }

    var stringFields : [String] {
        var rv : [String] = []
        for (field,isDouble) in zip(fields, columnIsDouble) {
            if !isDouble {
                rv.append(field)
            }
        }
        return rv
    }
    
    var fieldToIndex : [String:Int] {
        var rv : [String:Int] = [:]
        for (idx,field) in fields.enumerated() {
            rv[field] = idx
        }
        return rv
    }
    
    func doubleValues(for doubleFields : [String]) {
        let fieldToIndex : [String:Int] = self.fieldToIndex
        var fieldIndexes : [Int] = []
        for field in doubleFields {
            if let index = fieldToIndex[field] {
                fieldIndexes.append(index)
            }
        }
        
        for row in values {
            var newRow : [Double] = []
            for field in fields {
                let idx = fieldToIndex[field]
            }
        }
    }

    mutating func parseLines(lines : [String.SubSequence]){
        let trimCharSet = CharacterSet(charactersIn: "\"# ")
        
        for line in lines {
            let vals = line.split(separator: ",").map { $0.trimmingCharacters(in: trimCharSet)}
            
            if line.hasPrefix("#airframe") {
                for val in vals {
                    let keyval = val.split(separator: "=")
                    if keyval.count == 2 {
                        meta[String(keyval[0])] = keyval[1].trimmingCharacters(in: trimCharSet)
                    }
                }
            }else if line.hasPrefix("#"){
                units = vals
                for unit in units {
                    if unit.hasPrefix("yyy-") || unit.hasPrefix("hh:") || unit == "ident" || unit == "enum" {
                        columnIsDouble.append(false)
                    }else{
                        columnIsDouble.append(true)
                    }
                }
            }else if fields.count == 0 {
                fields = vals
            }else if vals.count == columnIsDouble.count {
                var doubleLine : [Double] = []
                var stringLine : [String] = []
                for (val, isDouble) in zip(vals,columnIsDouble) {
                    if isDouble {
                        if let dbl = Double(val) {
                            doubleLine.append(dbl)
                        }else{
                            doubleLine.append(.nan)
                        }
                    }else{
                        stringLine.append(val)
                    }
                }
                values.append(doubleLine)
                string.append(stringLine)
            }
        }
    }
}
