//
//  TimedDataByField.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 24/04/2022.
//

import Foundation
import RZUtils

public struct IndexedValuesByField<I : Comparable,T,F : Hashable> {
    public enum IndexedValuesByFieldError : Error {
        case inconsistentIndexOrder
        case inconsistentDataSize
        case unknownField
    }
    
    public typealias FieldsValues = [F:T]
    
    public struct IndexedValue {
        public let index : I
        public let value : T
    }
    
    public struct IndexedValues {
        public let indexes : [I]
        public let values : [T]
        
        public func dropFirst(_ k : Int) -> IndexedValues {
            return IndexedValues(indexes: [I]( self.indexes.dropFirst(k) ), values: [T]( self.values.dropFirst(k)) )
        }
    }
    
    private(set) var indexes : [I]
    private(set) var values : [F:[T]]
    
    var fields : [F] { return Array(values.keys) }
    var count : Int { return indexes.count }
    
    public init(fields : [F]){
        indexes = []
        values = [:]
        for field in fields {
            values[field] = []
        }
    }
    
    
    //MARK: - modify, append
    private mutating func indexCheckAndUpdate(index : I) throws {
        if let last = indexes.last {
            if index > last {
                indexes.append(index)
            }else if index < last {
                throw IndexedValuesByFieldError.inconsistentIndexOrder
            }
        }else{
            // nothing yet, insert date
            indexes.append(index)
        }
    }
    
    private mutating func updateField(field : F, element : T) throws {
        // if start and field missing, add dynamically
        if self.indexes.count == 1 && values[field] == nil {
            values[field] = []
        }
        
        guard let dataForField = values[field] else { throw IndexedValuesByFieldError.inconsistentDataSize }
        if dataForField.count != (indexes.count - 1) {
            throw IndexedValuesByFieldError.inconsistentDataSize
        }
        values[field]!.append(element)
    }
    public mutating func append(field : F, element : T, for index : I) throws {
        try self.indexCheckAndUpdate(index: index)
        
        try self.updateField(field: field, element: element)
    }
    
    public mutating func append(fieldsValues : [F:T], for index : I) throws {
        try self.indexCheckAndUpdate(index: index)

        for (field,value) in fieldsValues {
            try self.updateField(field: field, element: value)
        }
    }

    
    public mutating func append(fields : [F], elements: [T], for index : I) throws {
        try self.indexCheckAndUpdate(index: index)
        
        for (field,element) in zip(fields,elements) {
            try self.updateField(field: field, element: element)
        }
    }
    
    public func dropFirst(field : F, minimumMatchCount : Int = 1, matching : ((T) -> Bool)) -> IndexedValuesByField? {
        
        guard let fieldValues = self.values[field]
        else {
            return nil
        }
        
        var rv = IndexedValuesByField(fields: [F](self.values.keys))

        var found : Int = -1
        var matchCount : Int = 0
        for (idx,value) in fieldValues.enumerated() {
            if matching(value) {
                matchCount += 1
            }else{
                matchCount = 0
            }

            if matchCount >= minimumMatchCount {
                found = idx
                break
            }

        }

        if found != -1 {
            rv.indexes = [I](self.indexes.dropFirst(found))
            for (oneField,oneFieldValues) in self.values {
                rv.values[oneField] = [T](oneFieldValues.dropFirst(found))
            }
        }
        return rv
    }
    
    public func dropLast(field : F, matching : ((T) -> Bool)) -> IndexedValuesByField? {
        
        guard let fieldValues = self.values[field]
        else {
            return nil
        }
        
        var rv = IndexedValuesByField(fields: Array(self.values.keys))

        var found : Int = 0
        for (idx,value) in fieldValues.reversed().enumerated() {
            if matching(value) {
                found = idx
                break
            }
        }

        rv.indexes = [I](self.indexes.dropLast(found))
        for (oneField,oneFieldValues) in self.values {
            rv.values[oneField] = [T](oneFieldValues.dropLast(found))
        }
        return rv
    }
    
    //MARK: - access
    public func last(field : F, matching : ((T) -> Bool)? = nil) -> IndexedValue?{
        guard let fieldValues = self.values[field],
              let lastDate = self.indexes.last,
              let lastValue = fieldValues.last
        else {
            return nil
        }
        
        if let matching = matching {
            for (date,value) in zip(indexes.reversed(),fieldValues.reversed()) {
                if matching(value) {
                    return IndexedValue(index: date, value: value)
                }
            }
            return nil
        }else{
            return IndexedValue(index: lastDate, value: lastValue)
        }
    }

    public func first(field : F, matching : ((T) -> Bool)? = nil) -> IndexedValue?{
        guard let fieldValues = self.values[field],
              let firstDate = self.indexes.first,
              let firstValue = fieldValues.first
        else {
            return nil
        }
        
        if let matching = matching {
            for (date,value) in zip(indexes,fieldValues) {
                if matching(value) {
                    return IndexedValue(index: date, value: value)
                }
            }
            return nil
        }else{
            return IndexedValue(index: firstDate, value: firstValue)
        }
    }
    
    public func dateValue(for field : F, at index : Int) -> IndexedValue? {
        guard let fieldValues = self.values[field], index < self.indexes.count else { return nil }
        let value = fieldValues[index]
        let date = self.indexes[index]
        return IndexedValue(index: date, value: value)
    }

    public func value(for field : F, at index : Int) -> T? {
        guard let fieldValues = self.values[field], index < self.indexes.count else { return nil }
        let value = fieldValues[index]
        return value
    }
    
    public func fieldValue(at index : Int) -> FieldsValues {
        var rv : FieldsValues = [:]
        for (field,values) in self.values {
            if let value = values[safe: index] {
                rv[field] = value
            }
        }
        return rv
    }
    
    public subscript(_ field : F) -> IndexedValues? {
        guard let values = self.values[field] else { return nil }
        return IndexedValues(indexes: self.indexes, values: values)
    }
    
}

extension IndexedValuesByField  where T == Double, F == FlightLogFile.Field {
    public func valueStats(from : I, to : I) -> [F:ValueStats] {
        var rv : [F:ValueStats] = [:]
        var started : Bool = false
        for (idx,runningdate) in self.indexes.enumerated(){
            if runningdate > to {
                break
            }
            if runningdate >= from {
                if started {
                    for (field,values) in self.values {
                        rv[field]?.update(double: values[idx])
                    }
                }else{
                    for (field,values) in self.values {
                        rv[field] = ValueStats(value: values[idx], weight: 1.0, unit: field.unit)
                    }
                    started = true
                }
            }
        }
        return rv
    }
    
    public func max(for field : F) -> T? {
        guard let fieldValues = self.values[field] else { return nil }
        let value = fieldValues.max()
        return value
    }
    
    public func min(for field : F) -> T? {
        guard let fieldValues = self.values[field] else { return nil }
        let value = fieldValues.min()
        return value
    }
}

extension IndexedValuesByField  where T == Double, F == FlightLogFile.Field, I == Date {

    public func dataSeries(from : I? = nil, to : I? = nil) -> [F:GCStatsDataSerie] {
        var rv : [F:GCStatsDataSerie] = [:]
        var started : Bool = false
        for (idx,runningdate) in self.indexes.enumerated(){
            if let to = to, runningdate > to {
                break
            }
            if from == nil || runningdate >= from! {
                if started {
                    for (field,values) in self.values {
                        rv[field]?.add(GCStatsDataPoint(date: runningdate, andValue: values[idx]))
                    }
                }else{
                    for (field,values) in self.values {
                        rv[field] = GCStatsDataSerie()
                        rv[field]?.add(GCStatsDataPoint(date: runningdate, andValue: values[idx]))
                    }
                    started = true
                }
            }
        }
        return rv
    }

}
