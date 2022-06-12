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
import TabularData

class FlightData {
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
    
    //MARK: - Parsing State
    
    private struct ParsingState {
        var lastReportTime = Date()
        var totalSize = 0
        
        var fields : [Field] = []
        var columnIsDouble : [Bool] = []
        
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
        
        var units : [String] = []

        var data : FlightData
        
        var doubleLine : [Double] = []
        var stringLine : [String] = []
        
        init(data : FlightData){
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZ"
            self.data = data
        }
        
        mutating func process(line : [String]){
            guard let first = line.first else { return }
            
            if first.hasPrefix("#airframe") {
                for val in line {
                    let keyval = val.split(separator: "=")
                    if keyval.count == 2 {
                        let metaFieldDescription = String(keyval[0])
                        if let metaField = MetaField(rawValue: metaFieldDescription) {
                            data.meta[metaField] = String(keyval[1])
                        }else{
                            Logger.app.warning("Unknown meta field \(metaFieldDescription)")
                        }
                    }
                }
            }else if first.hasPrefix("#"){
                units = line
                for unit in units {
                    if unit.hasPrefix("yyy-") || unit.hasPrefix("hh:") || unit == "ident" || unit == "enum" {
                        columnIsDouble.append(false)
                    }else{
                        columnIsDouble.append(true)
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
                    }else{
                        fields.append(.Unknown)
                        Logger.app.warning("Unknown field \(fieldDescription)")
                    }
                    
                }
                fields = line.map { Field(rawValue: $0) ?? .Unknown }
                for (idx,(isDouble,unit)) in zip(columnIsDouble,units).enumerated() {
                    if isDouble {
                        let field = fields[idx]
                        let gcunit = GCUnit.from(logFileUnit: unit)
                        data.fieldsUnits[field] = gcunit
                    }
                }
                data.doubleFields = []
                data.stringFields = []
                for (field,isDouble) in zip(fields, columnIsDouble) {
                    if isDouble {
                        data.doubleFields.append(field)
                    }else{
                        data.stringFields.append(field)
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
                    data.coordinates.append(coord)
                }else{
                    data.coordinates.append(kCLLocationCoordinate2DInvalid)
                }
                data.values.append(doubleLine)
                data.strings.append(stringLine)
                if coord.latitude.isFinite && coord.longitude.isFinite {
                    let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    if let last = lastLocation {
                        runningDistance += location.distance(from: last)
                    }
                    lastLocation = location
                }
                data.distances.append(runningDistance)
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
        progress?.update(state: .progressing(0.0))

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
            Logger.app.info("parsed \(totalSize) bytes in \(Date().timeIntervalSince(start)) secs")
        }
    }
    
    //MARK: - parse Memory
    
    private func parse(array : [String.SubSequence], progress : ProgressReport? = nil){
        let start = Date()
        var state = ParsingState(data: self)
        var done_sofar = 0
        
        self.values.reserveCapacity(array.count)
        self.strings.reserveCapacity(array.count)
        
        let trimCharSet = CharacterSet(charactersIn: "\" ")
        progress?.update(state: .progressing(0.0), message: "Parsing Log")
        for line in array {
            progress?.update(state: .progressing(Double(done_sofar)/Double(array.count)))
            done_sofar += 1
            let vals = line.split(separator: ",").map { $0.trimmingCharacters(in: trimCharSet)}
            state.process(line: vals)
        }
        progress?.update(state: .complete)
        Logger.app.info("parsed \(array.count) lines in \(Date().timeIntervalSince(start)) secs")
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
