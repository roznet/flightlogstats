//
//  FlightData.swift
//  connectflight
//
//  Created by Brice Rosenzweig on 29/06/2021.
//

import Foundation
import RZUtils
import RZUtilsSwift

struct FlightData {
    var meta : [String:String] = [:]
    var units : [String] = []
    var fields : [String] = []
    var columnIsDouble : [Bool] = []
    /**
        * values columns are fields,
     */
    var values : [[Double]] = []
    var string : [[String]] = []
    var dates : [Date] = []
    
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
    
    var doubleFieldToIndex : [String:Int] {
        var rv : [String:Int] = [:]
        for (idx,field) in doubleFields.enumerated() {
            rv[field] = idx
        }
        return rv
    }

    var stringFieldToIndex : [String:Int] {
        var rv : [String:Int] = [:]
        for (idx,field) in stringFields.enumerated() {
            rv[field] = idx
        }
        return rv
    }

    /**
     * return array of values which are dict of field -> value
     */
    func values(for doubleFields : [String]) -> [ [String:Double] ] {
        let fieldToIndex : [String:Int] = self.doubleFieldToIndex
        
        var rv : [[String:Double]] = []
        
        for row in values {
            var newRow : [String:Double] = [:]
            for field in doubleFields {
                if let idx = fieldToIndex[field] {
                    let val = row[idx]
                    if !val.isNaN {
                        newRow[field] = val
                    }
                }
            }
            rv.append(newRow)
        }
        return rv
    }
    
    /**
        * return series for each field
     */
    func series(for doubleFields : [String]) -> [String:[Double]] {
        let fieldToIndex : [String:Int] = self.doubleFieldToIndex
        var rv : [String:[Double]] = [:]
        
        for field in doubleFields {
            rv[ field ] = []
        }
        
        for row in values {
            for field in doubleFields {
                if let idx = fieldToIndex[field] {
                    let val = row[idx]
                    rv[field]!.append(val)
                }
            }
        }
        return rv
    }
    
    func timeSeries(for doubleFields : [String]) -> ([String:[Double]],[Date]) {
        let fieldToIndex : [String:Int] = self.doubleFieldToIndex
        var rv : [String:[Double]] = [:]
        var validDates : [Date] = []
        
        for field in doubleFields {
            rv[ field ] = []
        }
        
        for (date,row) in zip(dates,values) {
            var valid : Bool = true
            for field in doubleFields {
                if let idx = fieldToIndex[field] {
                    if row[idx].isNaN {
                        valid = false
                        break
                    }
                }
            }
            if valid {
                for field in doubleFields {
                    if let idx = fieldToIndex[field] {
                        let val = row[idx]
                        rv[field]!.append(val)
                    }
                }
                validDates.append(date)
            }
        }
        return (rv,validDates)
    }

    mutating func parseLines(lines : [String.SubSequence]){
        let trimCharSet = CharacterSet(charactersIn: "\"# ")
        
        let dateIndex : Int = 0
        let timeIndex : Int = 1
        let offsetIndex : Int = 2
        
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm:ss ZZ"
        
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
                let dateString = String(format: "%@ %@ %@", vals[dateIndex], vals[timeIndex], vals[offsetIndex])
                if let date = formatter.date(from: dateString) {
                    dates.append(date)
                }else{
                    RZSLog.error("Failed to parse date")
                }
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
