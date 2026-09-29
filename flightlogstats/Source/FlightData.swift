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
import RZData

class FlightData {
    // how often to report progress
    private static let progressReportStep = 5
    
    
    typealias Field = FlightLogFile.Field
    typealias CategoricalValue = FlightLogFile.CategoricalValue
    typealias MetaField = FlightLogFile.MetaField
    
    private(set) var fieldsUnits : [Field:Dimension] = [:]
    
    private var categoricalDataFrame : DataFrame<Date,CategoricalValue,Field> = DataFrame<Date,String,Field>()
    private var doubleDataFrame : DataFrame<Date,Double,Field> = DataFrame<Date,Double,Field>()
    private var coordinateDataFrame : DataFrame<Date,CLLocationCoordinate2D,Field> = DataFrame<Date,CLLocationCoordinate2D,Field>()

    private(set) var meta : [MetaField:String] = [:]
    private(set) var doubleFields : [Field] = []
    private(set) var categoricalFields : [Field] = []
    
    private var values : [[Double]] = []
    private var strings : [[CategoricalValue]] = []
    private var dates : [Date] = []
    private var coordinatesArray : [CLLocationCoordinate2D] = []
    
    var coordinateColumn : DataFrame<Date,CLLocationCoordinate2D,Field>.Column {
        let df = self.coordinateDataFrame(for: [.Coordinate])
        guard let rv = df[.Coordinate] else { return DataFrame<Date,CLLocationCoordinate2D,Field>.Column(indexes: [], values: []) }
        return rv
    }

    var count : Int { return dates.count }
    var firstCoordinate : CLLocationCoordinate2D {
        return self.coordinatesArray.first { CLLocationCoordinate2DIsValid($0) } ?? kCLLocationCoordinate2DInvalid
    }
    var lastCoordinate : CLLocationCoordinate2D {
        return self.coordinatesArray.last { CLLocationCoordinate2DIsValid($0) } ?? kCLLocationCoordinate2DInvalid
    }

    var firstDate : Date? { return self.dates.first }
    var lastDate : Date? { return self.dates.last }
    
    private var sourceName : String? = nil
    
    private var doubleFieldToIndex : [Field:Int] {
        var rv : [Field:Int] = [:]
        for (idx,field) in doubleFields.enumerated() {
            rv[field] = idx
        }
        return rv
    }

    private var categoricalFieldToIndex : [Field:Int] {
        var rv : [Field:Int] = [:]
        for (idx,field) in categoricalFields.enumerated() {
            rv[field] = idx
        }
        return rv
    }
    
    private init() {}
    
    convenience init?(url: URL, maxLineCount: Int? = nil, lineSamplingFrequency : Int = 1, progress : ProgressReport? = nil){
        self.init()
        self.sourceName = url.lastPathComponent
        
        var inputSize = 0
        do {
            let resources = try url.resourceValues(forKeys: [.fileSizeKey] )
            if let fileSize = resources.fileSize {
                inputSize = fileSize
            }
        }catch{
            inputSize = 0
        }
        
        guard let inputStream = InputStream(url: url) else { return nil }
        do {
            try self.parse(inputStream: inputStream, totalSize: inputSize, maxLineCount: maxLineCount, lineSamplingFrequency: lineSamplingFrequency, progress: progress)
        }catch{
            return nil
        }
    }
        
    convenience init(inputStream : InputStream, maxLineCount: Int? = nil,
                     lineSamplingFrequency : Int = 1, progress : ProgressReport? = nil) throws {
        self.init()
        self.sourceName = "InputStream"
        try self.parse(inputStream: inputStream, maxLineCount: maxLineCount, lineSamplingFrequency: lineSamplingFrequency)
    }

    
    //MARK: - raw extracts
        
    /// doubles values for every field with data and with nan removed
    /// - Parameter doubleFields: fields to check for not a value
    /// - Parameter includeAllFields: true return all field, false only return felds checked for na
    /// - Returns: indexed for value  that are valid (will call dropna)
    func doubleDataFrame(for fields : [Field] = [], includeAllFields : Bool = true) -> DataFrame<Date,Double,Field> {
        // If not constructed yet (0 element) build the data frame from raw data.
        if self.doubleDataFrame.count == 0 {
            let cstart = Date()
            self.convertDataFrame()
            Logger.app.info("Converted \(self.doubleDataFrame.count) rows in \(Date().timeIntervalSince(cstart)) secs")
        }
        // if no input fields specified return everything
        if fields.count == 0 {
            return self.doubleDataFrame
        }else{
            return self.doubleDataFrame.dropna(fields: fields, includeAllFields: includeAllFields)
        }
    }

    /**
     *
     return each strings changes and assigned to the first date when the string appeared
     
     - Parameters:
     - stringFields: the field to collect the values for
     - start: nil or the date when the collection should start
     - Returns: DatesValuesByField where date is the first appearance of the string
     */
    func categoricalDataFrame(for stringFields : [Field] = [], includeAllFields : Bool = true) -> DataFrame<Date,CategoricalValue,Field> {
        if self.categoricalDataFrame.count == 0 {
            let cstart = Date()
            self.convertDataFrame()
            Logger.app.info("Converted \(self.categoricalDataFrame.count) rows in \(Date().timeIntervalSince(cstart)) secs")
        }
        if includeAllFields {
            return self.categoricalDataFrame
        }else{
            let rv = try? self.categoricalDataFrame.dataFrame(for: stringFields)
            return rv ?? self.categoricalDataFrame
        }
    }
        
    func coordinateDataFrame(for coordField : [Field]) -> DataFrame<Date,CLLocationCoordinate2D,Field> {
        if self.categoricalDataFrame.count == 0 {
            let cstart = Date()
            self.convertDataFrame()
            Logger.app.info("Converted \(self.categoricalDataFrame.count) rows in \(Date().timeIntervalSince(cstart)) secs")
        }
        return self.coordinateDataFrame
    }    
}

extension FlightData {
    //MARK: - Parsing State

    //
    private class ParsingState : CsvInterpreter {
        enum ColumnType {
            case double
            case category
            case ignore
        }
        
        var maxLineCount: Int?
        
        var lastReportTime = Date()
        var totalSize : Int
        var lineSamplingFrequency : Int
        
        var fields : [Field] = []
        var columnIsDouble : [ColumnType] = []
        var fieldsMap : [Field:Int] = [:]
        
        let dateIndex : Int = 0
        let timeIndex : Int = 1
        let offsetIndex : Int = 2
        
        var latitudeIndex : Int? = nil
        var longitudeIndex : Int? = nil

        // keep default format in list as if bad data need to try again the same
        let extraDateFormats = [ "dd/MM/yyyy HH:mm:ss ZZ", "yyyy-MM-dd HH:mm:ss ZZ" ]
        let formatter = DateFormatter()
        
        var skipped : Int = 0
        var lastLocation : CLLocation? = nil
        var runningDistance : CLLocationDistance = 0.0
        var firstDate : Date? = nil
        
        var units : [String] = []
        
        // date and offset columns and seconds of day of the last dated row, for the date shortcut
        var lastDateString : String? = nil
        var lastOffsetString : String? = nil
        var lastSecondsOfDay : Int? = nil

        var data : FlightData
        
        var doubleLine : [Double] = []
        var stringLine : [String] = []
        
        var doubleInputs : [Field:[Double]] = [:]
        var doubleInputsCount : Int = 0
        
        init(data : FlightData, totalSize : Int, maxLineCount: Int? = nil, lineSamplingFrequency : Int = 1, progress : ProgressReport? = nil){
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZ"
            self.data = data
            self.progress = progress
            self.totalSize = totalSize
            self.lineSamplingFrequency = lineSamplingFrequency
            self.maxLineCount = maxLineCount
            for calcField in FieldCalculation.calculatedFields {
                if calcField.requiredObservationCount > 0 {
                    self.doubleInputsCount = max(self.doubleInputsCount,calcField.requiredObservationCount)
                    for field in calcField.inputs {
                        self.doubleInputs[field] = []
                    }
                }
            }
        }
        var interpretStartTime : Date? = nil
        var progress : ProgressReport?
        
        func start() {
            self.interpretStartTime = Date()
            self.progress?.update(state: .progressing(0.0), message: .parsingInfo)
        }
        func finished() {
            self.progress?.update(state: .complete)
            if totalSize > 0 {
                let formatter = ByteCountFormatter()
                if let interpretStartTime = self.interpretStartTime {
                    let name = self.data.sourceName ?? ""
                    if lineSamplingFrequency != 1 {
                        Logger.app.info("\(name) Parsed \(formatter.string(fromByteCount: Int64(totalSize)))[1/\(lineSamplingFrequency)] in \(Date().timeIntervalSince(interpretStartTime)) secs")
                    }else{
                        Logger.app.info("\(name) Parsed \(formatter.string(fromByteCount: Int64(totalSize))) in \(Date().timeIntervalSince(interpretStartTime)) secs")
                    }
                }else{
                    Logger.app.info("Parsed \(formatter.string(fromByteCount: Int64(totalSize)))")
                }
            }
        }
        func process(line : [String], readCount : Int, lineCount : Int){
            guard let first = line.first else { return }
            
            if totalSize > 0 {
                progress?.update(state: .progressing(min(1.0,Double(readCount)/Double(totalSize))))
            }

            if first.hasPrefix("#airframe") {
                for val in line {
                    let keyval = val.split(separator: "=")
                    if keyval.count == 2 {
                        let metaFieldDescription = String(keyval[0])
                        if let metaField = MetaField(rawValue: metaFieldDescription) {
                            data.meta[metaField] = String(keyval[1]).replacingOccurrences(of: "\"", with: "")
                        }else{
                            Logger.app.warning("Unknown meta field \(metaFieldDescription)")
                        }
                    }
                }
            }else if first.hasPrefix("#"){
                units = line
                for unit in units {
                    if unit.hasPrefix("#yyy-") || unit.hasPrefix("hh:") {
                        columnIsDouble.append(.ignore)
                    }else if unit == "ident" || unit == "enum" {
                        columnIsDouble.append(.category)
                    }else{
                        columnIsDouble.append(.double)
                    }
                }
            }else if fields.count == 0 {
                fields = []
                for (idx,fieldDescription) in line.enumerated() {
                    if let field = Field(rawValue: fieldDescription) {
                        if field == .Latitude {
                            latitudeIndex = idx
                        }
                        if field == .Longitude {
                            longitudeIndex = idx
                        }
                        fields.append(field)
                        
                        if field.valueType == .categorical {
                            if idx < columnIsDouble.count {
                                columnIsDouble[idx] = .category
                            }
                        }
                    }else{
                        fields.append(.Unknown)
                        Logger.app.warning("Unknown field \(fieldDescription)")
                    }
                }
                fields = line.map { Field(rawValue: $0) ?? .Unknown }
                for (idx,(isDouble,unit)) in zip(columnIsDouble,units).enumerated() {
                    switch isDouble {
                    case .double:
                        let field = fields[idx]
                        let unit = Dimension.from(logFileUnit: unit)
                        data.fieldsUnits[field] = unit
                    case .category,.ignore:
                        break
                    }
                }
                data.doubleFields = []
                data.categoricalFields = []
                fieldsMap = [:]
                var idx = 0
                for (field,isDouble) in zip(fields, columnIsDouble) {
                    switch isDouble {
                    case .double:
                        data.doubleFields.append(field)
                        fieldsMap[field] = idx
                        idx += 1
                    case .category:
                        data.categoricalFields.append(field)
                    case .ignore:
                        break
                    }
                }
                
                // add calculated fields
                data.doubleFields.append(.Distance)
                data.fieldsUnits[.Distance] = UnitLength.nauticalMiles
                for field in FieldCalculation.calculatedFields {
                    switch field.outputType {
                    case .doubleArray,.double:
                        for f in field.outputs {
                            fieldsMap[f] = data.doubleFields.count
                            data.fieldsUnits[f] = f.unit
                        }
                        data.doubleFields.append(contentsOf: field.outputs)
                        
                    case .string:
                        data.categoricalFields.append(field.output)
                    }
                }
            }else if line.count == columnIsDouble.count {
                if lineCount % self.lineSamplingFrequency != 0 {
                    return
                }
                
                // Same date and offset columns as the previous row: offset its date by the
                // difference in time of day, saves a lot of time vs date parsing
                let secondsOfDay = FlightData.secondsOfDay(line[timeIndex])
                var dateProxied = false
                if let lastDate = data.dates.last,
                   let secondsOfDay = secondsOfDay,
                   let lastSecondsOfDay = self.lastSecondsOfDay,
                   line[dateIndex] == self.lastDateString,
                   line[offsetIndex] == self.lastOffsetString {
                    data.dates.append(lastDate.addingTimeInterval(TimeInterval(secondsOfDay - lastSecondsOfDay)))
                    dateProxied = true
                }
                if !dateProxied {
                    let dateString = String(format: "%@ %@ %@", line[dateIndex], line[timeIndex], line[offsetIndex])
                    if let date = formatter.date(from: dateString) {
                        data.dates.append(date)
                    }else{
                        if dateString.replacingOccurrences(of: " ", with: "").isEmpty {
                            // skip empty strings
                            return
                        }
                        
                        // if first one try few other format
                        if data.dates.count == 0{
                            for fmt in extraDateFormats {
                                formatter.dateFormat = fmt
                                if let date = formatter.date(from: dateString) {
                                    data.dates.append(date)
                                    break
                                }
                            }
                            if data.dates.count == 0 {
                                // never keep a row without its date: values and dates must stay aligned
                                if skipped < 5 {
                                    Logger.app.error("Failed to identify date format '\(dateString)'")
                                }
                                skipped += 1
                                return
                            }
                        }else{
                            // we already have dates, so
                            if skipped < 5 {
                                let skipped = skipped
                                Logger.app.error("Failed to parse date '\(dateString)' skipped=\(skipped)")
                            }
                            skipped += 1
                            return
                        }
                    }
                }
                self.lastDateString = line[dateIndex]
                self.lastOffsetString = line[offsetIndex]
                self.lastSecondsOfDay = secondsOfDay

                self.doubleLine.removeAll(keepingCapacity: true)
                self.stringLine.removeAll(keepingCapacity: true)
                
                var coord = CLLocationCoordinate2D(latitude: .nan, longitude: .nan)
                
                for (idx,(val, isDouble)) in zip(line,columnIsDouble).enumerated() {
                    switch isDouble {
                    case .double:
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
                    case .category:
                        stringLine.append(val)
                    case .ignore:
                        break
                    }
                }
                if coord.latitude.isFinite && coord.longitude.isFinite {
                    data.coordinatesArray.append(coord)
                    let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    if let last = lastLocation {
                        runningDistance += location.distance(from: last)
                    }
                    lastLocation = location

                }else{
                    data.coordinatesArray.append(kCLLocationCoordinate2DInvalid)
                }
                // match order with what was added for fields
                doubleLine.append(runningDistance/1852.0) // in nautical miles to be consistant with other fields
                
                // seconds since the previous kept row: the current date is already in
                // data.dates. Time going backwards (log restart) counts as no time.
                var elapsed : TimeInterval = 0.0
                if data.dates.count > 1 {
                    elapsed = max(0.0, data.dates[data.dates.count-1].timeIntervalSince(data.dates[data.dates.count-2]))
                }

                // first add all output of calculated double fields so they can
                // also be used in doubleInputs
                for calcField in FieldCalculation.calculatedFields {
                    if calcField.inputType == .doubles {
                        switch calcField.outputType {
                        case .double:
                            doubleLine.append(calcField.evaluate(line: doubleLine, fieldsMap: fieldsMap, previousLine: data.values.last, elapsed: elapsed))
                        case .doubleArray:
                            doubleLine.append(contentsOf:  calcField.evaluateToArray(line: doubleLine, fieldsMap: fieldsMap, previousLine: data.values.last, elapsed: elapsed))
                        case .string:
                            break
                        }
                    }
                }

                // Now build doubleArray inputs
                for field in self.doubleInputs.keys {
                    if let idx = fieldsMap[field] {
                        let val = doubleLine[idx]
                        self.doubleInputs[field]?.append(val)
                    }
                    if let count = self.doubleInputs[field]?.count, count > self.doubleInputsCount {
                        self.doubleInputs[field]?.removeFirst()
                    }
                }
                
                for calcField in FieldCalculation.calculatedFields {
                    if calcField.inputType == .doublesArray {
                        switch calcField.outputType {
                        case .string:
                            let previous = data.strings.last?[stringLine.count]
                            let newVal = calcField.evaluateToString(lines: self.doubleInputs, fieldsMap: fieldsMap, previous: previous)
                            
                            // If more than one observation, we will need to fill back the new value
                            // this is assuming the calculation is a look back: for example
                            // phase of flight, if altitude has gone up we are climbing, and mark climbing back to the
                            // beginning of the inputs. if 1 observation don't do anything
                            if calcField.requiredObservationCount > 1 {
                                // reset when value changes
                                var amountToFill : Int = 0
                                // if value changed, restart array and fill all the value for the current inputs
                                if let prevVal = previous, prevVal != newVal {
                                    for field in self.doubleInputs.keys {
                                        if let idx = fieldsMap[field] {
                                            let val = doubleLine[idx]
                                            if let cnt = self.doubleInputs[field]?.count, cnt > amountToFill {
                                                amountToFill = cnt
                                            }
                                            self.doubleInputs[field] = [val]
                                        }
                                    }
                                }
                                if amountToFill != 0 {
                                    let cnt = data.strings.count
                                    let downto = max(0,cnt - amountToFill)
                                    for idx in downto..<cnt {
                                        data.strings[idx][stringLine.count] = newVal
                                    }
                                    
                                }
                            }
                            stringLine.append(newVal)
                        case .double,.doubleArray:
                            break
                        }
                            
                    }
                }

                data.values.append(doubleLine)
                data.strings.append(stringLine)
            }
        }
    }
    
    //MARK: - parse stream
    
    /// seconds since midnight of a `HH:mm:ss` string, nil if it is not in that form
    static func secondsOfDay(_ time : String) -> Int? {
        var parts = (0, 0, 0)
        var index = 0
        var digits = 0
        for char in time.utf8 {
            if char == UInt8(ascii: ":") {
                guard digits > 0 else { return nil }
                index += 1
                digits = 0
                continue
            }
            guard char >= UInt8(ascii: "0") && char <= UInt8(ascii: "9"), index < 3 else { return nil }
            let digit = Int(char - UInt8(ascii: "0"))
            switch index {
            case 0: parts.0 = parts.0 * 10 + digit
            case 1: parts.1 = parts.1 * 10 + digit
            default: parts.2 = parts.2 * 10 + digit
            }
            digits += 1
        }
        guard index == 2, digits > 0 else { return nil }
        return parts.0 * 3600 + parts.1 * 60 + parts.2
    }

        
    func parse(inputStream : InputStream, totalSize : Int = 0, maxLineCount: Int? = nil,
               lineSamplingFrequency : Int = 1, progress : ProgressReport? = nil) throws {

        let parsingState = ParsingState(data: self, totalSize: totalSize, maxLineCount: maxLineCount,
                                        lineSamplingFrequency: lineSamplingFrequency, progress: progress)
        let bufferedStreamReader = BufferedStreamReader(inputStream: inputStream)
        try CsvParser.parse(bufferedStreamReader: bufferedStreamReader, interpreter: parsingState)
    }
    
    private func convertDataFrameSlow() {
        self.doubleDataFrame = DataFrame(indexes: self.dates, fields: self.doubleFields, rows: self.values)
        self.categoricalDataFrame = DataFrame(indexes: self.dates, fields: self.categoricalFields, rows: self.strings)
        self.coordinateDataFrame = DataFrame(indexes: self.dates, values: [.Coordinate:self.coordinatesArray])
    }
    
    /// Rows kept in the data frames: a repeated date keeps its first row, and time going
    /// backwards (the log restarted) drops everything before it. Shared by all frames so
    /// the double, categorical and coordinate frames line up row for row.
    static func keptRows(dates : [Date]) -> [Int] {
        guard var lastindex = dates.first else { return [] }
        
        var rv : [Int] = []
        rv.reserveCapacity(dates.count)
        for (row,index) in dates.enumerated() {
            if index < lastindex {
                rv.removeAll(keepingCapacity: true)
            }
            // edge case date is repeated
            if rv.count == 0 || index != lastindex {
                rv.append(row)
                lastindex = index
            }
        }
        return rv
    }
    
    private func convertDataFrame() {
        guard self.dates.first != nil else {
            return
        }
        
        // rows are appended to all four arrays together, guard anyway rather than trap
        let rowCount = min(self.dates.count, self.values.count, self.strings.count, self.coordinatesArray.count)
        if rowCount != self.dates.count {
            Logger.app.error("Inconsistent row counts dates=\(self.dates.count) values=\(self.values.count) strings=\(self.strings.count) coordinates=\(self.coordinatesArray.count)")
        }
        let rows = Self.keptRows(dates: Array(self.dates.prefix(rowCount)))
        let builtIndexes : [Date] = rows.map { self.dates[$0] }
        
        var builtValues : [Field:[Double]] = [:]
        for field in self.doubleFields {
            builtValues[field] = []
            builtValues[field]?.reserveCapacity(rows.count)
        }
        for row in rows {
            // for some reason doing it manually here is much faster than calling function on dataframe?
            for (field,element) in zip(doubleFields,self.values[row]) {
                builtValues[field]?.append(element)
            }
        }
        self.doubleDataFrame = DataFrame(indexes: builtIndexes, values: builtValues)

        var builtCategorical : [Field:[CategoricalValue]] = [:]
        for field in self.categoricalFields {
            builtCategorical[field] = []
            builtCategorical[field]?.reserveCapacity(rows.count)
        }
        for row in rows {
            for (field,element) in zip(categoricalFields,self.strings[row]) {
                builtCategorical[field]?.append(element)
            }
        }
        self.categoricalDataFrame = DataFrame(indexes: builtIndexes, values: builtCategorical)
        
        let builtCoordinates : [CLLocationCoordinate2D] = rows.map { self.coordinatesArray[$0] }
        self.coordinateDataFrame = DataFrame(indexes: builtIndexes, values: [.Coordinate:builtCoordinates])
    }
}
