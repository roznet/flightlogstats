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
    
    static var methodBuffered = true
    
    convenience init?(url: URL, progress : ProgressReport? = nil){
        self.init()
        
        if Self.methodBuffered {
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
                try self.parse(inputStream: inputStream, totalSize: inputSize, progress: progress)
            }catch{
                return nil
            }
        }else{
            var lines : [String.SubSequence] = []
            do {
                let str = try String(contentsOf: url, encoding: .macOSRoman)
                lines = str.split(whereSeparator: \.isNewline)
            }catch {
                Logger.app.error("Failed to read \(url.lastPathComponent) \(error.localizedDescription)")
                return nil
            }
                                    
            self.init(lines: lines, progress: progress)
        }
    }
    
    convenience init(lines : [String.SubSequence], progress : ProgressReport? = nil) {
        self.init()
        self.parse(array: lines, progress: progress)
    }
    
    convenience init(inputStream : InputStream,progress : ProgressReport? = nil) throws {
        self.init()
        try self.parse(inputStream: inputStream)
    }
    

    //MARK: - parse Memory
    
    private func parse(array : [String.SubSequence], progress : ProgressReport? = nil){
        let start = Date()
        var state = ParsingState(data: self)
        var done_sofar = 0
        
        self.values.reserveCapacity(array.count)
        self.strings.reserveCapacity(array.count)
        
        let trimCharSet = CharacterSet(charactersIn: "\" ")
        progress?.update(state: .progressing(0.0), message: .parsingInfo)
        for line in array {
            progress?.update(state: .progressing(Double(done_sofar)/Double(array.count)))
            done_sofar += 1
            let vals = line.split(separator: ",").map { $0.trimmingCharacters(in: trimCharSet)}
            state.process(line: vals)
        }
        progress?.update(state: .complete)
        Logger.app.info("Parsed \(array.count) lines in \(Date().timeIntervalSince(start)) secs")
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
        
    /// doubles values with nan removed
    /// - Parameter doubleFields: fields to check for not a value
    /// - Parameter includeAllFields: true return all field, false only return felds checked for na
    /// - Returns: indexed for value  that are valid (will call dropna)
    func doubleDataFrame(for fields : [Field] = [], includeAllFields : Bool = true) -> DataFrame<Date,Double,Field> {
        if self.doubleDataFrame.count == 0 {
            let cstart = Date()
            self.convertDataFrame()
            Logger.app.info("Converted \(self.doubleDataFrame.count) rows in \(Date().timeIntervalSince(cstart)) secs")
        }
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
    
    /// Will extract and compute parameters
    /// will compute statistics between date in the  array returning one stats per dates, the stats will start form the first value up to the
    /// first date in the input value, if the last date is before the end of the data, the end is skipped
    /// if a start is provided the stats starts from the first available row of data
    /// - Parameter dates: array of dates corresponding to the first date of the leg
    /// - Parameter start:first date to start statistics or nil for first date in data
    /// - Parameter end: last date (included) to collect statistics or nil for last date in data
    /// - Returns: statisitics computed between dates
    @available(*, deprecated, message: "don't use anymore, prefer doubleValues and extract from there" )
    func extract(dates extractDates : [Date], start : Date? = nil, end : Date? = nil) throws -> DataFrame<Date,ValueStats,Field> {
        var rv = DataFrame<Date,ValueStats,Field>(fields: self.doubleFields)
        
        // we need at least one date to extract and one date of data, else we'll return empty
        // last date should be past the last date (+10 seconds) so it's included
        if let firstExtractDate = extractDates.first,
           let lastDate = end ?? self.dates.last {
            // remove first from extractDates because we already collected it in firstExtractDate
            var remainingDates = extractDates.dropFirst()
            
            var nextExtractDate : Date = remainingDates.first ?? lastDate
            if remainingDates.count > 0 {
                remainingDates.removeFirst()
            }
            
            let startDate = start ?? firstExtractDate
            let firstDate = max(startDate,firstExtractDate)
            
            var current : [ValueStats] = []
            var currentExtractDate = startDate
            
            for (date,one) in zip(self.dates,self.values) {
                let include = date >= firstDate

                if date > lastDate {
                    break
                }
                
                if date > nextExtractDate {
                    if include {
                        do {
                            try rv.append(fields: self.doubleFields, elements: current, for: currentExtractDate)
                        }catch{
                            throw error
                        }
                    }
                    current = []
                    currentExtractDate = nextExtractDate
                    nextExtractDate = remainingDates.first ?? lastDate
                    if remainingDates.count > 0 {
                        remainingDates.removeFirst()
                    }
                }
                if include {
                    if current.count == 0 {
                        current = zip(one,self.doubleFields).map { ValueStats(value: $0, unit: $1.unit) }
                    }else{
                        for (idx,val) in one.enumerated() {
                            current[idx].update(double: val)
                        }
                    }
                }
            }
            // add last one if still there
            if current.count > 0 {
                do {
                    try rv.append(fields: self.doubleFields, elements: current, for: currentExtractDate)
                }catch{
                    throw error
                }

            }
        }
        return rv
    }
}

extension FlightData {
    //MARK: - Parsing State

    //
    private struct ParsingState {
        enum ColumnType {
            case double
            case category
            case ignore
        }
        
        var lastReportTime = Date()
        var totalSize = 0
        
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

        var data : FlightData
        
        var doubleLine : [Double] = []
        var stringLine : [String] = []
        
        var doubleInputs : [Field:[Double]] = [:]
        var doubleInputsCount : Int = 0
        
        init(data : FlightData){
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZ"
            self.data = data
            for calcField in FieldCalculation.calculatedFields {
                if calcField.requiredObservationCount > 0 {
                    self.doubleInputsCount = max(self.doubleInputsCount,calcField.requiredObservationCount)
                    for field in calcField.inputs {
                        self.doubleInputs[field] = []
                    }
                }
            }
        }
        
        mutating func process(line : [String]){
            guard let first = line.first else { return }
            
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
                // Usually date are +1, +2 or same, saves a lot of time vs date parsing to try to guess...
                var dateProxied = false
                if let lastDate = data.dates.last {
                    let lastDigit = Int(lastDate.timeIntervalSinceReferenceDate)
                    let suffix = line[timeIndex].suffix(1)
                    if suffix == "\( (lastDigit + 1) % 10)" {
                        data.dates.append(lastDate.addingTimeInterval(1.0) )
                        dateProxied = true
                    }else if suffix == "\( (lastDigit + 2) % 10)" {
                        data.dates.append(lastDate.addingTimeInterval(2.0) )
                        dateProxied = true
                    }else if suffix == "\( lastDigit % 10)" {
                        data.dates.append(lastDate )
                        dateProxied = true
                    }
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
                            if data.dates.count == 0 && skipped < 5 {
                                Logger.app.error("Failed to identify date format '\(dateString)'")
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

                self.doubleLine.removeAll()
                self.stringLine.removeAll()
                
                
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
                }else{
                    data.coordinatesArray.append(kCLLocationCoordinate2DInvalid)
                }
                if coord.latitude.isFinite && coord.longitude.isFinite {
                    let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    if let last = lastLocation {
                        runningDistance += location.distance(from: last)
                    }
                    lastLocation = location
                }
                // match order with what was added for fields
                doubleLine.append(runningDistance/1852.0) // in nautical miles to be consistant with other fields
                
                // first add all output of calculated double fields so they can
                // also be used in doubleInputs
                for calcField in FieldCalculation.calculatedFields {
                    if calcField.inputType == .doubles {
                        switch calcField.outputType {
                        case .double:
                            doubleLine.append(calcField.evaluate(line: doubleLine, fieldsMap: fieldsMap, previousLine: data.values.last))
                        case .doubleArray:
                            doubleLine.append(contentsOf:  calcField.evaluateToArray(line: doubleLine, fieldsMap: fieldsMap, previousLine: data.values.last))
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
    
    private enum State {
        case beginningOfDocument
        case endOfDocument
        
        
        case beginningOfLine
        case maybeEndOfLine
        case endOfLine
        
        case maybeInField
        case inField
        case endOfField

        case inQuotedField
        case maybeEndOfQuotedField
    }
    
    private struct CSVScalar  {
        static let CarriageReturn : UnicodeScalar = "\r"
        static let LineFeed : UnicodeScalar = "\n"
        static let DoubleQuote : UnicodeScalar = "\""
        static let Comma : UnicodeScalar = ","
        static let Space : UnicodeScalar = " "
    }
    
    enum ParseError : Error {
        case invalidStateForComma
        case invalidStateForNewLine
        case invalidStateForQuote
        case invalidStateForOtherChar
    }
    
    func parse(inputStream : InputStream, totalSize : Int = 0, progress : ProgressReport? = nil) throws {
        let start = Date()
        progress?.update(state: .progressing(0.0), message: .parsingInfo)

        var parsingState = ParsingState(data: self)
        //var done_sofar = 0
        
        let bufferedStreamReader = BufferedStreamReader(inputStream: inputStream)
        var state : State = .beginningOfDocument
        
        var fieldBuffer : [UInt8] = []
        
        var line : [String] = []
        
        while state != .endOfDocument {
            let byte = bufferedStreamReader.pop()
            switch byte {
            case .error(let error):
                Logger.app.error("Failed to read stream \(error.localizedDescription)")
                state = .endOfDocument
            case .endOfFile:
                state = .endOfDocument
            case .char(let char):
                
                let scalar = UnicodeScalar(char)
                if state == .beginningOfDocument {
                    state = .beginningOfLine
                }
                
                if state == .endOfLine {
                    state = .beginningOfLine
                }
                
                switch scalar {
                case CSVScalar.Comma:
                    switch state {
                    case .beginningOfLine:
                        state = .endOfField
                    case .inField, .maybeInField:
                        state = .endOfField
                    case .inQuotedField:
                        fieldBuffer.append(char)
                    case .maybeEndOfQuotedField,.endOfField:
                        state = .endOfField
                    default:
                        throw ParseError.invalidStateForComma
                    }
                case CSVScalar.CarriageReturn:
                    switch state {
                    case .endOfField, .beginningOfLine, .inField, .maybeInField, .maybeEndOfQuotedField:
                        state = .maybeEndOfLine
                    case .inQuotedField:
                        fieldBuffer.append(char)
                    default:
                        throw ParseError.invalidStateForNewLine
                    }
                case CSVScalar.LineFeed:
                    switch state {
                    case .endOfField, .beginningOfLine, .inField, .maybeInField, .maybeEndOfQuotedField:
                        state = .endOfLine
                    case .inQuotedField:
                        fieldBuffer.append(char)
                    case .maybeEndOfLine:
                        state = .beginningOfLine
                    default:
                        throw ParseError.invalidStateForNewLine
                    }
                case CSVScalar.Space:
                    switch state {
                    case .inField:
                        fieldBuffer.append(char)
                    default:
                        state = .maybeInField
                    }
                case CSVScalar.DoubleQuote:
                    switch state {
                    case .beginningOfLine, .endOfField:
                        state = .inQuotedField
                    case .maybeEndOfQuotedField:
                        // double double quote, to escape double quote
                        fieldBuffer.append(char)
                        state = .inQuotedField
                    case .inField:
                        fieldBuffer.append(char)
                    case .inQuotedField:
                        // first one
                        state = .maybeEndOfQuotedField
                    default:
                        throw ParseError.invalidStateForQuote
                    }
                default:
                    switch state {
                    case .beginningOfLine, .endOfField:
                        fieldBuffer.append(char)
                        state = .inField
                    case .maybeEndOfQuotedField:
                        state = .maybeEndOfQuotedField
                    case .maybeInField:
                        fieldBuffer.append(char)
                        state = .inField
                    case .inField, .inQuotedField:
                        fieldBuffer.append(char)
                    default:
                        throw ParseError.invalidStateForOtherChar
                    }
                }
            }
            if state == .endOfField || state == .endOfLine || state == .maybeEndOfLine || state == .endOfDocument {
                if let value = String(data: Data(fieldBuffer), encoding: .utf8) {
                    line.append(value)
                }else{
                    line.append("") // empty
                }
                fieldBuffer.removeAll()
                if state != .endOfField {
                    parsingState.process(line: line)
                    line.removeAll()
                    if totalSize > 0 {
                        progress?.update(state: .progressing(min(1.0,Double(bufferedStreamReader.readCount)/Double(totalSize))))
                    }
                }
            }
        }
        progress?.update(state: .complete)
        if totalSize > 0 {
            let formatter = ByteCountFormatter()
            Logger.app.info("Parsed \(formatter.string(fromByteCount: Int64(totalSize))) in \(Date().timeIntervalSince(start)) secs")
        }
    }
    
    private func convertDataFrame() {
        self.doubleDataFrame.clear(fields: self.doubleFields)
        self.categoricalDataFrame.clear(fields: self.categoricalFields)
        self.coordinateDataFrame = DataFrame(indexes: self.dates, values: [.Coordinate:self.coordinatesArray])
        self.doubleDataFrame.reserveCapacity(self.dates.capacity)
        self.categoricalDataFrame.reserveCapacity(self.dates.capacity)
        
        guard dates.first != nil else { return }
        
        var lastdate = dates.first!
        for (date,row) in zip(dates,values) {
            if date < lastdate {
                Logger.app.info("Resetting inconsistent date after \(self.doubleDataFrame.count) out of \(self.dates.count)")
                self.doubleDataFrame.clear(fields: self.doubleFields)
                self.doubleDataFrame.reserveCapacity(self.dates.capacity)
            }
            // edge case date is repeated
            if self.doubleDataFrame.count == 0 || date != lastdate {
                self.doubleDataFrame.unsafeFastAppend(fields: self.doubleFields, elements: row, for: date)
                lastdate = date
            }
        }
        
        lastdate = dates.first!
        for (date,row) in zip(dates,strings) {
            if date < lastdate {
                self.categoricalDataFrame.clear(fields: self.categoricalFields)
                self.categoricalDataFrame.reserveCapacity(self.dates.capacity)
            }
            if self.categoricalDataFrame.count == 0 || date != lastdate {
                self.categoricalDataFrame.unsafeFastAppend(fields: self.categoricalFields, elements: row, for: date)
                lastdate = date
            }
        }
    }
}
