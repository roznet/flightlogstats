//
//  FlightLeg.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 07/05/2022.
//

import Foundation
import CoreLocation
import OSLog
import RZData

struct FlightLeg {
    typealias Field = FlightLogFile.Field
    typealias CategoricalValue = FlightLogFile.CategoricalValue
    typealias CategoricalValueStats = CategoricalStats<CategoricalValue>
    
    enum LegInfo : String {
        case start_time = "Start"
        case end_time = "End"
    }
    
    let timeRange : TimeRange
    var start : Date { return timeRange.start }
    var end : Date { return timeRange.end }
    
    private var valueStats : [Field:ValueStats]
    private var categoricalStats : [Field:CategoricalValueStats]
    private(set) var categoricalValues : [Field:CategoricalValue]
    
    var groupedFields : [Field] { return Array(self.categoricalValues.keys).sorted { $0.order < $1.order } }
    
    var fields : [Field] {
        return (Array(valueStats.keys) + Array(categoricalStats.keys)).sorted { $0.order < $1.order }
    }
    
    init(timeRange: TimeRange, categoricalValues : [Field : CategoricalValue], valueStats: [Field : ValueStats], categoricalStats: [Field : CategoricalValueStats] ) {
        self.categoricalValues = categoricalValues
        self.timeRange = timeRange
        self.valueStats = valueStats
        self.categoricalStats = categoricalStats
    }
    
    func valueStats(field : Field) -> ValueStats? {
        return self.valueStats[field]
    }
    
    func categoricalValue(field: Field) -> CategoricalValue? {
        return self.categoricalValues[field]
    }
    func categoricalValueStats(field: Field) -> CategoricalValueStats? {
        return self.categoricalStats[field]
    }

    func format(which : LegInfo, displayContext : DisplayContext = DisplayContext(), reference : Date? = nil) -> String {
        switch which {
        case .start_time:
            return displayContext.format(time: self.timeRange.start, since: self.timeRange.start, reference: reference)
        case .end_time:
            return displayContext.format(time: self.timeRange.end, since: self.timeRange.start, reference: reference)
        }
    }

    static func legs(from data : FlightData,
                     byfields : [Field],
                     start : Date? = nil,
                     end : Date? = nil) -> [FlightLeg] {
        let identifiers : DataFrame<Date,String,Field> = data.categoricalDataFrame(for: byfields).sliced(start: start).dataFrameForValueChange(fields: byfields)
        return self.extract(from: data, identifiers: identifiers, start: start, end: end)
    }
    
    static func legs(from data : FlightData, interval : TimeInterval, start : Date? = nil, end : Date? = nil) -> [FlightLeg] {
        let values = data.doubleDataFrame().sliced(start: start,end: end)
        let schedule = values.indexes.regularShedule(interval: interval)
        let identifiers = DataFrame<Date,String,Field>(indexes: schedule, values: [:])
        return self.extract(from: data, identifiers: identifiers, start : start, end : end)
    }
    private static func extract(from data : FlightData,
                        identifiers : DataFrame<Date,String,Field>,
                     start : Date? = nil,
                     end : Date? = nil) -> [FlightLeg] {
        var rv : [FlightLeg] = []
        
        do {
            let values = data.doubleDataFrame()
            let categorical = data.categoricalDataFrame()
            
            let valuesStats : DataFrame<Date,ValueStats,Field> = try values.extractValueStats(indexes: identifiers.indexes, start: start, end: end, units: data.fieldsUnits)
            let categoricalStats : DataFrame<Date,CategoricalValueStats,Field> = try categorical.extractCategoricalStats(indexes: identifiers.indexes, start: start, end: end)
            
            for idx in 0..<identifiers.count {
                if var endTime = end ?? identifiers.indexes.last {
                   let startTime = identifiers.indexes[idx]
                    
                    if idx + 1 < identifiers.count {
                        endTime = identifiers.indexes[idx+1]
                    }
                    
                    let categoricalValues = identifiers.row(at: idx)
                    var validStats : [Field:ValueStats] = [:]
                    
                    for (field,val) in valuesStats.row(at: idx) {
                        if val.isValid {
                            validStats[field] = val
                        }
                    }
                    let leg = FlightLeg(timeRange: TimeRange(start: startTime, end: endTime),
                                        categoricalValues: categoricalValues,
                                        valueStats: validStats,
                                        categoricalStats: categoricalStats.row(at: idx))
                    rv.append(leg)
                }

            }
        }catch{
            Logger.app.error("Failed to extract route \(error.localizedDescription)")
        }
        return rv
    }
}

extension FlightLeg : CustomStringConvertible {
    var description: String {
        return "FlightLeg(\(start))"
    }
}

extension Array where Element == FlightLeg {
    typealias Field = FlightLogFile.Field

    var valueStatsByField : [Field:[ValueStats]] {
        var rv : [Field:[ValueStats]] = [:]
        
        // first collect and initialize superset of fields
        for element in self {
            for f in element.fields {
                rv[f] = []
            }
        }
        for element in self {
            for f in rv.keys {
                if let v = element.valueStats(field: f) {
                    rv[f]?.append(v)
                }else{
                    rv[f]?.append(ValueStats.invalid)
                }
            }
        }
        
        return rv
    }
    
}

extension FlightLeg.LegInfo : CustomStringConvertible {
    var description : String { return self.rawValue }
}
