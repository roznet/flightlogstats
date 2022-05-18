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
import RZFlight

typealias ProcessingProgressReport = (_ : Double) -> Void

struct FlightData {
    // how often to report progress
    private static let progressReportStep = 5
    
    
    typealias Field = FlightLogFile.Field
    typealias MetaField = FlightLogFile.MetaField
    
    private var fieldsUnits : [Field:GCUnit] = [:]
    /**
        * values columns are fields,
     */
    private var values : [[Double]] = []
    private var strings : [[String]] = []

    private(set) var meta : [MetaField:String] = [:]
    private(set) var dates : [Date] = []
    private(set) var doubleFields : [Field] = []
    private(set) var stringFields : [Field] = []
    
    private(set) var coordinates : [CLLocationCoordinate2D] = []
    private(set) var distances : [CLLocationDistance] = []

    var count : Int { return dates.count }
    var firstCoordinate : CLLocationCoordinate2D {
        return self.coordinates.first { CLLocationCoordinate2DIsValid($0) } ?? kCLLocationCoordinate2DInvalid
    }
    var lastCoordinate : CLLocationCoordinate2D {
        return self.coordinates.last { CLLocationCoordinate2DIsValid($0) } ?? kCLLocationCoordinate2DInvalid
    }

    private var doubleFieldToIndex : [Field:Int] {
        var rv : [Field:Int] = [:]
        for (idx,field) in doubleFields.enumerated() {
            rv[field] = idx
        }
        return rv
    }

    private var stringFieldToIndex : [Field:Int] {
        var rv : [Field:Int] = [:]
        for (idx,field) in stringFields.enumerated() {
            rv[field] = idx
        }
        return rv
    }
    
    private init() {}
    
    init?(url: URL, progress : ProcessingProgressReport? = nil){
        guard let str = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = str.split(whereSeparator: \.isNewline)
        
        self.init(lines: lines, progress: progress)
    }

    
    init(lines : [String.SubSequence], progress : ProcessingProgressReport? = nil) {
        self.init()
        self.parseLines(lines: lines, progress: progress)
    }
    
    private mutating func parseLines(lines : [String.SubSequence], progress : ProcessingProgressReport? = nil){
        var fields : [Field] = []
        var columnIsDouble : [Bool] = []
        
        let trimCharSet = CharacterSet(charactersIn: "\"# ")
        
        let dateIndex : Int = 0
        let timeIndex : Int = 1
        let offsetIndex : Int = 2
        
        var latitudeIndex : Int? = nil
        var longitudeIndex : Int? = nil

        // keep default format in list as if bad data need to try again the same
        let extraDateFormats = [ "dd/MM/yyyy HH:mm:ss ZZ", "yyyy-MM-dd HH:mm:ss ZZ" ]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZ"
        
        var skipped : Int = 0
        var lastLocation : CLLocation? = nil
        var runningDistance : CLLocationDistance = 0.0
        
        var done_sofar = 0
        let done_step = lines.count / 10
        var units : [String] = []
        for line in lines {
            if done_sofar % done_step == 0, let progress = progress {
                progress(Double(done_sofar)/Double(lines.count))
            }
            done_sofar += 1
            let vals = line.split(separator: ",").map { $0.trimmingCharacters(in: trimCharSet)}
            
            if line.hasPrefix("#airframe") {
                for val in vals {
                    let keyval = val.split(separator: "=")
                    if keyval.count == 2 {
                        let metaFieldDescription = String(keyval[0])
                        if let metaField = MetaField(rawValue: metaFieldDescription) {
                            meta[metaField] = keyval[1].trimmingCharacters(in: trimCharSet)
                        }else{
                            Logger.app.warning("Unknown meta field \(metaFieldDescription)")
                        }
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
                fields = []
                for (idx,fieldDescription) in vals.enumerated() {
                    if let field = Field(rawValue: fieldDescription) {
                        if field == .Latitude {
                            latitudeIndex = idx
                        }
                        if field == .Longitude {
                            longitudeIndex = idx
                        }
                        fields.append(field)
                    }else{
                        fields.append(.Unknown)
                        Logger.app.warning("Unknown field \(fieldDescription)")
                    }
                    
                }
                fields = vals.map { Field(rawValue: $0) ?? .Unknown }
                for (idx,(isDouble,unit)) in zip(columnIsDouble,units).enumerated() {
                    if isDouble {
                        let field = fields[idx]
                        let gcunit = GCUnit.from(logFileUnit: unit)
                        fieldsUnits[field] = gcunit
                    }
                }
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
                var coord = CLLocationCoordinate2D(latitude: .nan, longitude: .nan)
                
                for (idx,(val, isDouble)) in zip(vals,columnIsDouble).enumerated() {
                    if isDouble {
                        if let dbl = Double(val) {
                            if idx == longitudeIndex {
                                coord.longitude = dbl
                            }
                            if idx == latitudeIndex {
                                coord.latitude = dbl
                            }
                            doubleLine.append(dbl)
                        }else{
                            doubleLine.append(.nan)
                        }
                    }else{
                        stringLine.append(val)
                    }
                }
                if coord.latitude.isFinite && coord.longitude.isFinite {
                    coordinates.append(coord)
                }else{
                    coordinates.append(kCLLocationCoordinate2DInvalid)
                }
                values.append(doubleLine)
                strings.append(stringLine)
                if coord.latitude.isFinite && coord.longitude.isFinite {
                    let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    if let last = lastLocation {
                        runningDistance += location.distance(from: last)
                    }
                    lastLocation = location
                }
                distances.append(runningDistance)
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

        //MARK: - external and derived info
    func fetchAirports(completion : @escaping ([Airport]) -> Void){
        guard CLLocationCoordinate2DIsValid(self.firstCoordinate) && CLLocationCoordinate2DIsValid(self.lastCoordinate)
        else {
            completion([])
            return
        }
            
        Airport.near(coord: self.firstCoordinate, count: 1, reporting: false){
            startAirports in
            Airport.near(coord: self.lastCoordinate, count: 1, reporting: false){
                endAirports in
                var rv : [Airport] = []
                if let start = startAirports.first {
                    rv.append(start)
                }
                if let end = endAirports.first {
                    rv.append(end)
                }
                completion(rv)
            }
        }
    }

    
    //MARK: - raw extracts
    
    /**
     * return array of values which are dict of field -> value
     */
    func values(for doubleFields : [Field]) -> [ [Field:Double] ] {
        let fieldToIndex : [Field:Int] = self.doubleFieldToIndex
        
        var rv : [[Field:Double]] = []
        
        for row in values {
            var newRow : [Field:Double] = [:]
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
    
    func datesDoubles(for doubleFields : [Field]) -> DatesValuesByField<Double,Field> {
        let fieldToIndex : [Field:Int] = self.doubleFieldToIndex
        var rv = DatesValuesByField<Double,Field>(fields: doubleFields)
        
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
    func datesStrings(for stringFields : [Field]) -> DatesValuesByField<String,Field> {
        let fieldToIndex : [Field:Int] = self.stringFieldToIndex
        var rv = DatesValuesByField<String,Field>(fields: stringFields)
        
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
    func extract(dates : [Date], start : Date? = nil) throws -> DatesValuesByField<ValueStats,Field> {
        var rv = DatesValuesByField<ValueStats,Field>(fields: self.doubleFields)
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
}
