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

/**
 A leg will contain the statistics `ValueStats` and `CategoricalValueStats` for a set of entries in the logfile between two times
 They can be created either by specifying the times of the split for the entries or when the values of some categorical field changes in the data
 The stats will be calculated for all the `Field` found in the `DataFrame` constituing the original data

 If the `FlightLeg` is created by specifying the times of the split, the `categoricalValues` will be empty
 If the `FlightLeg` is created by specifying the values of the categorical fields, the `categoricalValues` will contain the values of the fields
 that where constant for that leg
 */
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
    
    /**
     contructor for internal use, that takes the precomputed `ValueStats` and `CategoricalData`
     this function is private, and the only way to create a `FlightLeg` is through the static `legs` function
     */
    private init(timeRange: TimeRange, categoricalValues : [Field : CategoricalValue], valueStats: [Field : ValueStats], categoricalStats: [Field : CategoricalValueStats] ) {
        self.categoricalValues = categoricalValues
        self.timeRange = timeRange
        self.valueStats = valueStats
        self.categoricalStats = categoricalStats
    }
    
    /**
    ValueStats for a given field representing the stats over the points of the leg
    */
    func valueStats(field : Field) -> ValueStats? {
        return self.valueStats[field]
    }
    /**
     CategoricalValueStats for a given field representing the stats over the points of the leg
     */
    func categoricalValueStats(field: Field) -> CategoricalValueStats? {
        return self.categoricalStats[field]
    }
    
    /**
     CategoricalValue that were constant over the time range of the leg when the leg was created
     by looking at the changes in specific categorical fields

     if the leg was created by specifying the time range, this will be empty
     */
    func categoricalValue(field: Field) -> CategoricalValue? {
        return self.categoricalValues[field]
    }

    func format(which : LegInfo, displayContext : DisplayContext = DisplayContext(), reference : Date? = nil) -> String {
        switch which {
        case .start_time:
            return displayContext.format(time: self.timeRange.start, since: self.timeRange.start, reference: reference)
        case .end_time:
            return displayContext.format(time: self.timeRange.end, since: self.timeRange.start, reference: reference)
        }
    }

    /**
    main function to create legs from a `FlightData` object by specifying the fields that should be constant over the leg
    - parameter data: the `FlightData` object to extract the legs from
    - parameter byfields: the fields that should be constant over the leg, if the value of any of these fields changes, a new leg will be created
    - parameter start: the start of the time range to extract the legs from, if nil, the start of the data will be used
    - parameter end: the end of the time range to extract the legs from, if nil, the end of the data will be used
    */
    static func legs(from data : FlightData,
                     byfields : [Field],
                     start : Date? = nil,
                     end : Date? = nil) -> [FlightLeg] {
        let identifiers : DataFrame<Date,String,Field> = data.categoricalDataFrame(for: byfields).sliced(start: start).dataFrameForValueChange(fields: byfields)
        return self.extract(from: data, identifiers: identifiers, start: start, end: end)
    }
    
    /**
    function to create legs from a `FlightData` object by specifying the time interval between each leg
    - parameter data: the `FlightData` object to extract the legs from
    - parameter interval: the time interval that each leg should cover
    - parameter start: the start of the time range to extract the legs from, if nil, the start of the data will be used
    - parameter end: the end of the time range to extract the legs from, if nil, the end of the data will be used
    */
    static func legs(from data : FlightData,
                     interval : TimeInterval,
                     start : Date? = nil,
                     end : Date? = nil) -> [FlightLeg] {
        let values = data.doubleDataFrame().sliced(start: start,end: end)
        let schedule = values.indexes.regularShedule(interval: interval)
        let identifiers = DataFrame<Date,String,Field>(indexes: schedule, values: [:])
        return self.extract(from: data, identifiers: identifiers, start : start, end : end)
    }
    
    /**
    The main extract function that takes the `DataFrame` of identifiers and extracts the legs from the data

    Both the time based and the field based functions call this function. They construct the `DataFrame` of identifiers differently, but the rest of the logic is the same.

    The logic is as follows:
    - for each identifier, extract the `ValueStats` and `CategoricalValueStats` for the time range of the leg
    - if the leg is the first leg, or the identifier is different from the previous leg, create a new leg
    - if the leg is not the first leg, and the identifier is the same as the previous leg, add the `ValueStats` and `CategoricalValueStats` to the previous leg
    */
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
