//
//  FlightData.swift
//  connectflight
//
//  Created by Brice Rosenzweig on 29/06/2021.
//

import Foundation
import OSLog
import RZUtils
import RZUtilsSwift


struct FlightData {
    private var units : [String] = []
    /**
        * values columns are fields,
     */
    private var values : [[Double]] = []
    private var strings : [[String]] = []

    private(set) var meta : [String:String] = [:]
    private(set) var dates : [Date] = []
    private(set) var doubleFields : [String] = []
    private(set) var stringFields : [String] = []

    var count : Int { return dates.count }
    
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
    
    private init() {}
    
    init?(url: URL){
        guard let str = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = str.split(whereSeparator: \.isNewline)
        
        self.init(lines: lines)
    }

    
    init(lines : [String.SubSequence]) {
        self.init()
        self.parseLines(lines: lines)
    }
    
    private mutating func parseLines(lines : [String.SubSequence]){
        var fields : [String] = []
        var columnIsDouble : [Bool] = []
        
        let trimCharSet = CharacterSet(charactersIn: "\"# ")
        
        let dateIndex : Int = 0
        let timeIndex : Int = 1
        let offsetIndex : Int = 2
        
        // keep default format in list as if bad data need to try again the same
        let extraDateFormats = [ "dd/MM/yyyy HH:mm:ss ZZ", "yyyy-MM-dd HH:mm:ss ZZ" ]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZ"
        
        var skipped : Int = 0
        
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
                    if dateString.replacingOccurrences(of: " ", with: "").isEmpty {
                        // skip empty strings
                        continue
                    }
                    
                    // if first one try few other format
                    if dates.count == 0{
                        for fmt in extraDateFormats {
                            formatter.dateFormat = fmt
                            if let date = formatter.date(from: dateString) {
                                dates.append(date)
                                break
                            }
                        }
                        if dates.count == 0 && skipped < 5 {
                            Logger.app.error("Failed to identify date format '\(dateString)'")
                            skipped += 1
                            continue
                        }
                    }else{
                        // we already have dates, so
                        if skipped < 5 {
                            Logger.app.error("Failed to parse date '\(dateString)' skipped=\(skipped)")
                        }
                        skipped += 1
                        continue
                    }
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
            self.doubleFields = []
            for (field,isDouble) in zip(fields, columnIsDouble) {
                if isDouble {
                    self.doubleFields.append(field)
                }
            }
            self.stringFields = []
            for (field,isDouble) in zip(fields, columnIsDouble) {
                if !isDouble {
                    self.stringFields.append(field)
                }
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
    
    func datesDoubles(for doubleFields : [String]) -> DatesValuesByField<Double,String> {
        let fieldToIndex : [String:Int] = self.doubleFieldToIndex
        var rv = DatesValuesByField<Double,String>(fields: doubleFields)
        
        var lastDate : Date? = nil
        
        for (date,row) in zip(dates,values) {
            var valid : Bool = true
            
            // skip if twice the same date
            if let lastDate = lastDate, date == lastDate {
                continue
            }
            lastDate = date
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
                        do {
                            try rv.append(field: field, element: val, for: date)
                        }catch{
                            Logger.app.error("Failed to create serie for \(field) at \(date)")
                            continue
                        }
                    }
                }
            }
        }
        return rv
    }

    /***
        return each strings changes and corresponding date
     */
    func datesStrings(for stringFields : [String]) -> DatesValuesByField<String,String> {
        let fieldToIndex : [String:Int] = self.stringFieldToIndex
        var rv = DatesValuesByField<String,String>(fields: stringFields)
        
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
                            if rv.last(field: field)?.value != val {
                                changed = true
                            }
                        }
                    }
                }
                
                if changed {
                    for field in stringFields {
                        if let idx = fieldToIndex[field] {
                            let val = row[idx]
                            do {
                                try rv.append(field: field, element: val, for: date)
                            }catch{
                                Logger.app.error("Failed to create serie for \(field) at \(date)")
                                continue
                            }
                        }
                    }
                    first = false
                }
            }
        }
        return rv
    }
        
    /// Will extract and compute parameters
    /// will compute statistics between date in the  array returning one stats per dates, the stats will start form the first value up to the
    /// first date in the input value, if the last date is before the end of the data, the end is skipped
    /// if a start is provided the stats starts from the first available row of data
    /// - Parameter dates: array of dates,
    /// - Parameter start:first date to start statistics or nil
    /// - Returns: statisitics computed between dates
    func extract(dates : [Date], start : Date? = nil) throws -> DatesValuesByField<ValueStats,String> {
        var rv = DatesValuesByField<ValueStats,String>(fields: self.doubleFields)
        var nextExtractDate : Date? = dates.first
        var remainingDates = dates.dropFirst()

        if let firstDate = start ?? self.dates.first {
            var current : [ValueStats] = []
            
            for (date,one) in zip(self.dates,self.values) {
                if date < firstDate {
                    continue
                }
                if let nextDate = nextExtractDate {
                    if date > nextDate {
                        do {
                            try rv.append(fields: self.doubleFields, elements: current, for: nextDate)
                        }catch{
                            throw error
                        }
                        current = []
                        nextExtractDate = remainingDates.first
                        remainingDates = remainingDates.dropFirst()
                        
                        if nextExtractDate == nil {
                            break
                        }
                    }
                    if current.count == 0 {
                        current = one.map { ValueStats(value: $0) }
                    }else{
                        for (idx,val) in one.enumerated() {
                            current[idx].update(with: val)
                        }
                    }
                }else{
                    // no next date, stop
                    break
                }
            }
        }
        
        return rv
    }
    
    static let coordinateField = "coordinate"
    
    func coordinates(latitudeField : String = "Latitude", longitudeField : String = "Longitude") -> DatesValuesByField<CLLocationCoordinate2D,String> {
        var rv = DatesValuesByField<CLLocationCoordinate2D,String>(fields: [Self.coordinateField])
        if let latitudeIndex = self.doubleFieldToIndex[latitudeField],
           let longitudeIndex = self.doubleFieldToIndex[longitudeField] {
            for (date,row) in zip(dates,values) {
                let latitude = row[latitudeIndex]
                let longitude = row[longitudeIndex]
                if latitude.isFinite && longitude.isFinite {
                    do {
                        try rv.append(field: Self.coordinateField, element: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), for: date)
                    }catch{
                        Logger.app.error("Failed to create coordinate for \(date)")
                    }
                }
            }
        }
        return rv
    }
}
