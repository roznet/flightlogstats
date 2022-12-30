//
//  FlightData+Summarized.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 19/11/2022.
//

import Foundation
import RZData

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
        }
        
        init(field:Field, type:ExportedValueType){
            self.field = field
            self.type = type
        }
    }
        
    struct ExportedCategorical : Hashable {
        let field : Field
        let type : ExportedCategoricalType
        
        var key : String { "\(self.field.rawValue).\(self.type.rawValue)" }
        
        init?(key: String) {
            let split = key.split(separator: ".", maxSplits: 1)
            guard
                split.count == 2,
                let fieldString = split.first,
                let metricString = split.last,
                let field = Field(rawValue: String(fieldString)),
                let type = ExportedCategoricalType(rawValue: String(metricString))
            else {
                return nil
            }
            
            self.field = field
            self.type = type
        }
        
        init(field: Field, type: ExportedCategoricalType){
            self.field = field
            self.type = type
        }

    }
    
    var values : DataFrame<Date,Double,ExportedValue>
    var categoricals : DataFrame<Date,CategoricalValue,ExportedCategorical>
    
    init(legs : [FlightLeg], valueDefs : [Field:[ExportedValueType]], categoricalDefs : [Field:[ExportedCategoricalType]] ) throws {
        /*var indexes : [Date] = []
        var values : [ExportedValue:[Double]]
        var categoricals : [ExportedCategorical:[CategoricalValue]]
        */
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
        }
    }
    
    static func defaultExport(legs : [FlightLeg]) throws -> FlightLogFileGroupBy {
        let valuesDefs : [Field:[ExportedValueType]] = [.Distance:[.total],
                                                        .Latitude:[.start],
                                                        .Longitude:[.start],
                                                  .E1_EGT_Max:[.max,.min],
                                                  .FTotalizerT:[.total]]
        
        let categoricalDefs : [Field:[ExportedCategoricalType]] = [.AfcsOn:[.mostFrequent], .E1_EGT_MaxIdx:[.end]]
        
        return try FlightLogFileGroupBy(legs: legs, valueDefs: valuesDefs, categoricalDefs: categoricalDefs)
    }
    
    func byRows(indexName : String, identifiers : [String:String] = [:]) ->  ByRows {
        var fields : [String] = []
        var rows : [[String]] = []

        //fields: idenfitiers, index, categorical, values

        let categoricalFields = self.categoricals.fields
        let valueFields = self.values.fields
        
        fields.append(contentsOf: identifiers.keys)
        fields.append(indexName)
        fields.append(contentsOf: categoricalFields.map { $0.key } )
        fields.append(contentsOf: valueFields.map { $0.key } )
        
        for (idx,date) in self.categoricals.indexes.enumerated() {
            var row : [String] = []
            
            row.append(contentsOf: identifiers.values)
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
}
