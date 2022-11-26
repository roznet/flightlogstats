//
//  TimedDataByField.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 24/04/2022.
//

import Foundation
import RZUtils

//DataFrame
public struct IndexedValuesByField<I : Comparable,T,F : Hashable> {
    public enum IndexedValuesByFieldError : Error {
        case inconsistentIndexOrder
        case inconsistentDataSize
        case unknownField
    }
    
    //Row
    public typealias FieldsValues = [F:T]
    
    public struct IndexedValue {
        public let index : I
        public let value : T
    }
    
    //Column
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
    
    public init() {
        indexes = []
        values = [:]
    }
    
    mutating public func reserveCapacity(_ capacity : Int){
        indexes.reserveCapacity(capacity)
        for k in values.keys {
            values[k]?.reserveCapacity(capacity)
        }
    }
    
    mutating public func clear(fields : [F] = []) {
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
        values[field, default: []].append(element)

        if values[field, default: []].count != indexes.count {
            throw IndexedValuesByFieldError.inconsistentDataSize
        }
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

    public mutating func unsafeFastAppend(fields : [F], elements : [T], for index : I) {
        self.indexes.append(index)
        for (field,element) in zip(fields,elements) {
            self.values[field, default: []].append(element)
        }
    }
    
    
    public mutating func append(fields : [F], elements: [T], for index : I) throws {
        try self.indexCheckAndUpdate(index: index)
        
        for (field,element) in zip(fields,elements) {
            try self.updateField(field: field, element: element)
        }
    }
    
    public func dropFirst(index : I) -> IndexedValuesByField? {
        guard let found = self.indexes.firstIndex(of: index) else { return nil }
        
        var rv = IndexedValuesByField(fields: [F](self.values.keys))
        rv.indexes = [I](self.indexes.dropFirst(found))
        for (field,values) in self.values {
            rv.values[field] = [T](values.dropFirst(found))
        }
        return rv
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
    
    //MARK: - Transform
    
    /// Returned array sliced from start to end.
    /// - Parameters:
    ///   - start: any index that are greater than or equal to start are included. if nil starts at the begining
    ///   - end: any index that are strictly less than end are included, if nil ends at the end
    /// - Returns: new indexvaluesbyfield
    public func sliced(start : I? = nil, end : I? = nil) -> IndexedValuesByField {
        guard self.indexes.count > 0 && ( start != nil || end != nil ) else { return self }
        
        var indexStart : Int = 0
        var indexEnd : Int = self.indexes.count
        
        
        if let start = start {
            indexStart = self.indexes.firstIndex { $0 >= start } ?? 0
        }
        if let end = end {
            if let found = self.indexes.lastIndex(where: { $0 < end }) {
                indexEnd = self.indexes.index(after: found)
            }
        }
        var rv = IndexedValuesByField(fields: self.fields)
        rv.indexes = [I](self.indexes[indexStart..<indexEnd])
        for (field,value) in self.values {
            rv.values[field] = [T](value[indexStart..<indexEnd])
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
    
    public func indexedValue(for field : F, at index : Int) -> IndexedValue? {
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
    
    public func fieldsValues(at index : Int) -> FieldsValues {
        var rv : FieldsValues = [:]
        for (field,values) in self.values {
            if let value = values[safe: index] {
                rv[field] = value
            }
        }
        return rv
    }
    
    public func indexedValues(for field : F) -> IndexedValues? {
        guard let values = self.values[field] else { return nil }
        return IndexedValues(indexes: self.indexes, values: values)
    }
    public subscript(_ field : F) -> IndexedValues? {
        return self.indexedValues(for: field)
    }
    
}

extension IndexedValuesByField where T : FloatingPoint {
    public func dropna(fields : [F], includeAllFields : Bool = false) -> IndexedValuesByField {
        let outputFields = includeAllFields ? self.fields : fields.compactMap( { self.values[$0] != nil ? $0 : nil } )
        let checkFields = fields.compactMap { self.values[$0] != nil ? $0 : nil }
        
        guard outputFields.count > 0 else { return self }
        
        var rv = IndexedValuesByField(fields: outputFields)
        rv.reserveCapacity(self.count)
        
        for (idx,index) in self.indexes.enumerated() {
            var valid : Bool = true
            for field in checkFields {
                let val = self.values[field]![idx]
                if !val.isFinite {
                    valid = false
                    break
                }
            }
            if valid {
                rv.unsafeFastAppend(fields: outputFields, elements: outputFields.map { self.values[$0]![idx] }, for: index)
            }
        }
        return rv
    }
    

}

extension IndexedValuesByField where T : Equatable {
    public func indexesForValueChange(fields : [F]) -> IndexedValuesByField {
        var rv = IndexedValuesByField(fields: self.fields)
        
        guard !fields.map({ self.values[$0] != nil }).contains(false) else { return rv }
        
        var last : [T] = []
        
        for (idx,index) in self.indexes.enumerated() {
            var add : Bool = (last.count != fields.count)
            let vals = fields.map { self.values[$0]![idx] }
            if !add {
                add = vals != last
            }
            last = vals
            if add {
                let row = fields.map { self.values[$0]![idx] }
                rv.unsafeFastAppend(fields: fields, elements: row, for: index)
            }
        }
        return rv
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

extension IndexedValuesByField : Sequence {
    ///MARK: Iterator
    public struct IndexedValuesByFieldIterator : IteratorProtocol {
        let values : IndexedValuesByField
        var idx : Int
        var element : [F:T] = [:]
        
        public init(_ indexedValues : IndexedValuesByField) {
            self.values = indexedValues
            self.idx = 0
        }
        public mutating func next() -> (I,[F:T])? {
            guard idx < values.indexes.count else { return nil }
                
            let index = values.indexes[idx]
            for (field,serie) in values.values {
                element[field] = serie[idx]
            }
            idx += 1
            return (index,element)
        }
    }
    public func makeIterator() -> IndexedValuesByFieldIterator {
        return IndexedValuesByFieldIterator(self)
    }
}
