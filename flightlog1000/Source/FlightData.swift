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
    private var units : [String] = []
    private var fields : [String] = []
    private var columnIsDouble : [Bool] = []
    /**
        * values columns are fields,
     */
    private var values : [[Double]] = []
    private var strings : [[String]] = []

    private(set) var dates : [Date] = []
    
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
    
    private var doubleFieldToIndex : [String:Int] {
        var rv : [String:Int] = [:]
        for (idx,field) in doubleFields.enumerated() {
            rv[field] = idx
        }
        return rv
    }

    private var stringFieldToIndex : [String:Int] {
        var rv : [String:Int] = [:]
        for (idx,field) in stringFields.enumerated() {
            rv[field] = idx
        }
        return rv
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
                strings.append(stringLine)
            }
        }
    }

    //MARK: - raw extracts
    
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

    /***
        return each strings changes and corresponding date
     */
    func strings(for stringFields : [String]) -> ([String:[String]],[Date]) {
        let fieldToIndex : [String:Int] = self.stringFieldToIndex
        var rv : [String:[String]] = [:]
        var validDates : [Date] = []
        
        for field in stringFields {
            rv[ field ] = []
        }
        var first = true
        
        for (date,row) in zip(dates,strings) {
            var valid : Bool = true
            for field in stringFields {
                if let idx = fieldToIndex[field] {
                    if row[idx].isEmpty {
                        valid = false
                        break
                    }
                }
            }
            if valid {
                var changed = first
                if !first {
                    for field in stringFields {
                        if let idx = fieldToIndex[field] {
                            let val = row[idx]
                            if rv[field]!.last! != val {
                                changed = true
                            }
                        }
                    }
                }
                
                if changed {
                    for field in stringFields {
                        if let idx = fieldToIndex[field] {
                            let val = row[idx]
                            rv[field]!.append(val)
                        }
                    }
                    validDates.append(date)
                    first = false
                }
            }
        }
        return (rv,validDates)
    }
    
    func coordinates(latitudeField : String = "Latitude", longitudeField : String = "Longitude") -> [CLLocationCoordinate2D] {
        var rv : [CLLocationCoordinate2D] = []
        if let latitudeIndex = self.doubleFieldToIndex[latitudeField],
           let longitudeIndex = self.doubleFieldToIndex[longitudeField] {
            for row in values {
                let latitude = row[latitudeIndex]
                let longitude = row[longitudeIndex]
                if latitude.isFinite && longitude.isFinite {
                    rv.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                }
            }
        }
        return rv
    }
}
