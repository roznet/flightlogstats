//
//  FlightData+Summarized.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 19/11/2022.
//

import Foundation
import RZData
import FMDB
import RZUtils
import OSLog
/*
 * Stats
 *   per minute:
 *      time start
 *      distance total
 *      long/lat start
 
 *      engine on/off maxfreq
 *      phase climb/descent/cruise/ground maxfreq
 
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
 
 *      CHTn max/min/median/maxI,minI
 *      EGTn max/min/median/maxI,minI
 *      TITn max/min/median/maxI,minI
 
 * calc type:
 *    start/end: first value, last value
 *    min/max/avg/minI/maxI/median
 *    total: last value - first value
 *    maxfreq: value most frequent
 
 */

extension Date {
    func roundedToNearest(interval : TimeInterval) -> Date {
        return Date(timeIntervalSinceReferenceDate: round(self.timeIntervalSinceReferenceDate/interval) * interval )
    }
    
    func withinOneSecond(of : Date) -> Bool {
        let diff = self.timeIntervalSinceReferenceDate - of.timeIntervalSinceReferenceDate
        return diff > -0.5 && diff < 0.5
    }
}

class FlightLogFileGroupBy  {
    enum FlightLogFileExportError : Error {
        case inconsitentIndexesSize
    }
    
    typealias Field = FlightLogFile.Field
    typealias CategoricalValue = FlightLogFile.CategoricalValue
    typealias ByRows = (fields: [String], rows:[[String]])

    typealias ExportedValueType = ValueStats.Metric
    typealias ExportedCategoricalType = CategoricalStats<CategoricalValue>.Metric
    
    struct ExportedValue : Hashable {
        let field : Field
        let type : ExportedValueType
        
        var key : String { "\(self.field.rawValue).\(self.type.rawValue)" }
        var sqlColumnName : String { "\"\(self.key)\"" }
        
        init?(key: String) {
            let split = key.split(separator: ".", maxSplits: 1)
            guard
                split.count == 2,
                let fieldString = split.first,
                let metricString = split.last,
                let field = Field(rawValue: String(fieldString)),
                let type = ExportedValueType(rawValue: String(metricString))
            else {
                return nil
            }
            
            self.field = field
            self.type = type

            if self.field.valueType != .value {
                return nil
            }
        }
        
        init(field:Field, type:ExportedValueType){
            self.field = field
            self.type = type
        }
    }
        
    struct ExportedCategorical : Hashable {
        let field : Field
        let type : ExportedCategoricalType?
        
        var key : String {
            if let type = self.type {
                return "\(self.field.rawValue).\(type.rawValue)"
            } else {
                return self.field.rawValue
            }
        }
        var sqlColumnName : String { "\"\(self.key)\"" }
        
        init?(key: String) {
            let split = key.split(separator: ".", maxSplits: 1)
            if
                split.count == 2,
                let fieldString = split.first,
                let metricString = split.last,
                let field = Field(rawValue: String(fieldString)),
                let type = ExportedCategoricalType(rawValue: String(metricString)){
                self.type = type
                self.field = field
            }else if let field = Field(rawValue: String(key)) {
                self.type = nil
                self.field = field
            }else{
                return nil
            }
            if self.field.valueType != .categorical {
                return nil
            }
        }
        
        init(field: Field, type: ExportedCategoricalType?){
            self.field = field
            self.type = type
        }

    }
    
    var values : DataFrame<Date,Double,ExportedValue>
    var categoricals : DataFrame<Date,CategoricalValue,ExportedCategorical>
    
    // logFileName if only one there
    var logFileName : String? {
        if let fns = self.categoricals[ExportedCategorical(field: .LogFileName, type: nil)]?.uniqueValues, fns.count == 1 {
            return fns.first
        }else{
            return nil
        }
    }
    
    var logFileNames : [String] {
        if let fns = self.categoricals[ExportedCategorical(field: .LogFileName, type: nil)]?.uniqueValues {
            return fns
        }else{
            return []
        }

    }
    
    init(legs : [FlightLeg], valueDefs : [Field:[ExportedValueType]], categoricalDefs : [Field:[ExportedCategoricalType]], constants : [Field:CategoricalValue] = [:] ) throws {
        self.values = DataFrame()
        self.categoricals = DataFrame()
        
        for leg in legs {
            for (field,types) in valueDefs {
                for type in types {
                    let value = leg.valueStats(field: field)?.value(for: type) ?? .nan
                    try self.values.append(field: ExportedValue(field: field, type: type), element: value, for: leg.start)
                }
            }
            for (field,types) in categoricalDefs {
                for type in types {
                    let value = leg.categoricalValueStats(field: field)?.value(for: type) ?? ""
                    try self.categoricals.append(field: ExportedCategorical(field: field, type: type), element: value, for: leg.start)
                }
            }
            for (field,constValue) in constants {
                self.categoricals.add(field: ExportedCategorical(field: field, type: nil),
                                      column: DataFrame.Column(indexes: self.categoricals.indexes, values: self.categoricals.indexes.map { _ in constValue }))
            }
        }
    }
    
    static func defaultExport(logFileName : String, legs : [FlightLeg]) throws -> FlightLogFileGroupBy {
        let valuesDefs : [Field:[ExportedValueType]] = [
            .Distance:[.total],
            .Latitude:[.start],
            .Longitude:[.start],
            .AltMSL:[.average],
            .OAT:[.average],
            .IAS:[.average],
            .TAS:[.average],
            .GndSpd:[.average],
            .volt1:[.average],
            .volt2:[.average],
            .amp1:[.max,.min],
            .FQtyT:[.start],
            .FTotalizerT:[.total],
            .E1_FFlow:[.average,.max,.min],
            .E1_MAP:[.average,.max,.min],
            .E1_RPM:[.average,.max,.min],
            .E1_OilP:[.max,.min],
            .E1_OilT:[.max,.min],
            .E1_EGT_Max:[.max,.min],
            .E1_EGT1:[.max,.min],
            .E1_EGT2:[.max,.min],
            .E1_EGT3:[.max,.min],
            .E1_EGT4:[.max,.min],
            .E1_EGT5:[.max,.min],
            .E1_EGT6:[.max,.min],
            .E1_CHT1:[.max,.min],
            .E1_CHT2:[.max,.min],
            .E1_CHT3:[.max,.min],
            .E1_CHT4:[.max,.min],
            .E1_CHT5:[.max,.min],
            .E1_CHT6:[.max,.min],

        ]
        
        let categoricalDefs : [Field:[ExportedCategoricalType]] = [
            .AfcsOn:[.mostFrequent],
            .RollM:[.mostFrequent],
            .PitchM:[.mostFrequent],
            .E1_EGT_MaxIdx:[.end]
        ]
        
        return try FlightLogFileGroupBy(legs: legs, valueDefs: valuesDefs, categoricalDefs: categoricalDefs, constants: [.LogFileName:logFileName])
    }
    
    func byRows(indexName : String = "Date") ->  ByRows {
        var fields : [String] = []
        var rows : [[String]] = []

        //fields: idenfitiers, index, categorical, values

        let categoricalFields = self.categoricals.fields
        let valueFields = self.values.fields
        
        fields.append(indexName)
        fields.append(contentsOf: categoricalFields.map { $0.key } )
        fields.append(contentsOf: valueFields.map { $0.key } )
        
        for (idx,date) in self.categoricals.indexes.enumerated() {
            var row : [String] = []
            
            row.append(date.ISO8601Format())
            for field in categoricalFields {
                row.append(self.categoricals[field]?[idx] ?? "")
            }
            for field in valueFields {
                if let val = self.values[field]?[idx] {
                    row.append(String(val))
                }else{
                    row.append("")
                }
            }
            rows.append(row)
        }
        
        return ByRows(fields: fields, rows: rows)
    }
    
   init(from db:FMDatabase, table : String) {
       self.values = DataFrame()
       self.categoricals = DataFrame()
       
        let indexName = "Date"
        
        //Get list of columns in table
        var sql = "PRAGMA table_info(\(table))"
        if let rs = db.executeQuery(sql, withArgumentsIn: []) {
            while rs.next() {
                let name = rs.string(forColumn: "name")!
                if name == indexName {
                    continue
                }
                if name == "LogFileName" {
                    self.categoricals.add(field: ExportedCategorical(field: .LogFileName, type: nil),
                                          column: DataFrame.Column(indexes: [], values: []))

                }else if let exportedCategorical = ExportedCategorical(key: name) {
                    self.categoricals.add(field: exportedCategorical, column: DataFrame.Column(indexes: [], values: []))
                }else if let exportedValue = ExportedValue(key: name) {
                    self.values.add(field: exportedValue, column: DataFrame.Column(indexes: [], values: []))
                }
            }
        }else{
            Logger.app.error("Failed to execute sql \(sql)")
        }
       let categoricalFields = self.categoricals.fields
       let valueFields = self.values.fields
       
       sql = "SELECT \(indexName),\(categoricalFields.map { $0.sqlColumnName }.joined(separator: ",")),\(valueFields.map { $0.sqlColumnName }.joined(separator: ",")) FROM \(table) ORDER BY Date"
        if let rs = db.executeQuery(sql, withArgumentsIn: []) {
            while rs.next() {
                let date = rs.date(forColumn: indexName)!
                for field in categoricalFields {
                    let value = rs.string(forColumn: field.key) ?? ""
                    try? self.categoricals.unsafeFastAppend(field: field, element: value, for: date)
                }
                for field in valueFields {
                    let value = rs.double(forColumn: field.key)
                    try? self.values.unsafeFastAppend(field: field, element: value, for: date)
                }
            }
        }else{
            Logger.app.error("Failed to execute sql \(db.lastErrorMessage()) \(sql)")
        }
    }

    //
    func merge(with other: FlightLogFileGroupBy) {
        // merge other first so the value for existing indexes comes from other
        let mergedValues = other.values.merged(with: self.values)
        let mergedCategoricals = other.categoricals.merged(with: self.categoricals)
        self.values = mergedValues
        self.categoricals = mergedCategoricals
    }
    // save to db
    func save(to db:FMDatabase, table : String) {
        let indexName = "Date"
        
        let categoricalFields = self.categoricals.fields
        let valueFields = self.values.fields
        
        guard
            let logFileNames = categoricals[ExportedCategorical(field: .LogFileName, type: nil)]?.uniqueValues,
            logFileNames.count > 0
        else {
            return
        }
        
        if !db.tableExists(table) {
            if !db.executeStatements("CREATE TABLE \(table) (\(indexName) DATETIME, LogFileName TEXT)"){
                Logger.app.error("Failed to execute sql \(db.lastErrorMessage())")
            }
            if !db.executeStatements("CREATE INDEX \(table)_LogFileName ON \(table) (LogFileName)"){
                Logger.app.error("Failed to execute sql \(db.lastErrorMessage())")
            }
        }
        logFileNames.forEach {
            logFileName in
            if !db.executeUpdate("DELETE FROM \(table) WHERE \"LogFileName\" = ?", withArgumentsIn: [logFileName]) {
                Logger.app.error("Failed to execute sql \(db.lastErrorMessage())")
            }
        }
        
        for field in categoricalFields {
            if field.field == .LogFileName {
                // special handling as it's indexed
                continue
            }
            if !db.columnExists(field.key, inTableWithName: table){
                if !db.executeStatements("ALTER TABLE \(table) ADD \(field.sqlColumnName) TEXT") {
                    Logger.app.error("Failed to execute sql \(db.lastErrorMessage())")
                }
            }
        }
        for field in valueFields {
            if !db.columnExists(field.key, inTableWithName: table){
                if !db.executeStatements("ALTER TABLE \(table) ADD \(field.sqlColumnName) REAL") {
                    Logger.app.error("Failed to execute sql \(db.lastErrorMessage())")
                }
            }
        }
        for (idx,date) in self.categoricals.indexes.enumerated() {
            
            var columns : [String] = ["Date"]
            var values : [Any] = [date]

            for field in categoricalFields {
                if field.field == .LogFileName {
                    //special case for index, logfilename is the name of the column
                    columns.append( field.field.rawValue )
                    values.append( self.categoricals[field]?[idx] ?? "")
                }else{
                    columns.append( field.sqlColumnName )
                    values.append( self.categoricals[field]?[idx] ?? "")
                }
            }
            for field in valueFields {
                if let val = self.values[field]?[idx] {
                    columns.append(field.sqlColumnName)
                    values.append(val)
                }
            }
            let colExpr = columns.joined(separator: ",")
            let params : [String] = columns.map { _ in "?" }
            let paramsExpr = params.joined(separator: ",")
            let sql = "INSERT INTO \(table) (\(colExpr)) VALUES (\(paramsExpr))"
            if !db.executeUpdate(sql, withArgumentsIn: values) {
                Logger.app.error("Failed to execute sql \(db.lastErrorMessage())")
            }
        }
    }
}
