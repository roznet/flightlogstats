//
//  GroupBy.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 19/11/2022.
//

import Foundation
import RZUtils

extension IndexedValuesByField  {
    private struct ExtractIndexes {
        private var remainingIndexes : [I]
        
        private var start : I?
        private var end : I?
        
        // Output Variable
        private(set) var currentExtractIndex : I
        private(set) var beforeStart : Bool = false
        private(set) var afterEnd : Bool = false
        private(set) var reachedNext : Bool = false

        init?(extractIndexes : [I],
              start : I?,
              end : I?)
        {
            // require at least one extractIndex and one Index
            if let firstExtractIndex = extractIndexes.first{
                self.start = start
                self.end = end
                
                self.currentExtractIndex = firstExtractIndex
                self.remainingIndexes = [I](extractIndexes.dropFirst())
                
            }else{
                return nil
            }
        }
        
        mutating func next() {
            if let first = self.remainingIndexes.first {
                self.currentExtractIndex = first
                self.remainingIndexes = [I](self.remainingIndexes.dropFirst())
            }
        }
        
        mutating func looking(at index : I){
            self.beforeStart = self.start != nil && index < self.start!
            self.afterEnd = self.end != nil && index > self.end!
            
            if let next = self.remainingIndexes.first {
                self.reachedNext = index >= next
            }else{
                self.reachedNext = false
            }
        }
    }

    /// Will extract and compute parameters
    /// will compute statistics between date in the  array returning one stats per dates, the stats will start form the first value up to the
    /// first date in the input value, if the last date is before the end of the data, the end is skipped
    /// if a start is provided the stats starts from the first available row of data
    /// - Parameter dates: array of dates corresponding to the first date of the leg
    /// - Parameter start:first date to start statistics or nil for first date in data
    /// - Parameter end: last date (included) to collect statistics or nil for last date in data
    /// - Returns: statisitics computed between dates
    func extract<C>(indexes extractIndexes : [I],
                    createCollector : (F,T) -> C,
                    updateCollector : (inout C?,T) -> Void,
                    start : I? = nil,
                    end : I? = nil) throws -> IndexedValuesByField<I,C,F> {
        var rv = IndexedValuesByField<I,C,F>(fields: self.fields)
        
        // we need at least one date to extract and one date of data, else we'll return empty
        // last date should be past the last date (+10 seconds) so it's included
        if var indexExtract = ExtractIndexes(extractIndexes: extractIndexes,
                                             start: start,
                                             end: end) {
            
            var current : [F:C] = [:]
            
            for (row,index) in self.indexes.enumerated() {
                indexExtract.looking(at: index)

                if indexExtract.beforeStart {
                    continue
                }
                
                if indexExtract.afterEnd {
                    break
                }
                
                if indexExtract.reachedNext {
                    do {
                        try rv.append(fieldsValues: current, for: indexExtract.currentExtractIndex)
                    }catch{
                        throw error
                    }
                    current = [:]
                    indexExtract.next()
                }
                if current.count == 0 {
                    //current = zip(self.fields,one).map { C(field: $0, value: $1) }
                    for (field,fieldValues) in self.values {
                        current[field] = createCollector(field,fieldValues[row])
                    }
                }else{
                    for (field,fieldValues) in self.values {
                        updateCollector(&current[field],fieldValues[row])
                    }
                }
            }
            // add last one if still there
            if current.count > 0 {
                do {
                    try rv.append(fieldsValues: current, for: indexExtract.currentExtractIndex)
                }catch{
                    throw error
                }
            }
        }
        return rv
    }
}

extension IndexedValuesByField where T == Double {
    
    /// Will extract and compute parameters
    /// will compute statistics between date in the  array returning one stats per dates, the stats will start form the first value up to the
    /// first date in the input value, if the last date is before the end of the data, the end is skipped
    /// if a start is provided the stats starts from the first available row of data
    /// - Parameter dates: array of dates corresponding to the first date of the leg
    /// - Parameter start:first date to start statistics or nil for first date in data
    /// - Parameter end: last date (included) to collect statistics or nil for last date in data
    /// - Returns: statisitics computed between dates
    func extractValueStats(indexes extractIndexes : [I],
                 start : I? = nil,
                 end : I? = nil,
                 units : [F:GCUnit] = [:]) throws -> IndexedValuesByField<I,ValueStats,F> {
        var rv = IndexedValuesByField<I,ValueStats,F>(fields: self.fields)
        
        // we need at least one date to extract and one date of data, else we'll return empty
        // last date should be past the last date (+10 seconds) so it's included
        if var indexExtract = ExtractIndexes(extractIndexes: extractIndexes,
                                             start: start,
                                             end: end) {
            
            var current : [F:ValueStats] = [:]
            
            for (row,index) in self.indexes.enumerated() {
                indexExtract.looking(at: index)
                
                if indexExtract.beforeStart {
                    continue
                }
                
                if indexExtract.afterEnd {
                    break
                }
                
                if indexExtract.reachedNext {
                    do {
                        try rv.append(fieldsValues: current, for: indexExtract.currentExtractIndex)
                    }catch{
                        throw error
                    }
                    current = [:]
                    indexExtract.next()
                }
                
                if current.count == 0 {
                    //current = zip(self.fields,one).map { C(field: $0, value: $1) }
                    for (field,fieldValues) in self.values {
                        current[field] = ValueStats(value:fieldValues[row],unit: units[field])
                    }
                }else{
                    for (field,fieldValues) in self.values {
                        current[field]?.update(double: fieldValues[row])
                    }
                }
            }
            // add last one if still there
            if current.count > 0 {
                do {
                    try rv.append(fieldsValues: current, for: indexExtract.currentExtractIndex)
                }catch{
                    throw error
                }
            }
        }
        return rv
    }
}

extension IndexedValuesByField where T : Hashable {
    
    /// Will extract and compute parameters
    /// will compute statistics between date in the  array returning one stats per dates, the stats will start form the first value up to the
    /// first date in the input value, if the last date is before the end of the data, the end is skipped
    /// if a start is provided the stats starts from the first available row of data
    /// - Parameter dates: array of dates corresponding to the first date of the leg
    /// - Parameter start:first date to start statistics or nil for first date in data
    /// - Parameter end: last date (included) to collect statistics or nil for last date in data
    /// - Returns: statisitics computed between dates
    func extractCategoricalStats(indexes extractIndexes : [I],
                 start : I? = nil,
                 end : I? = nil) throws -> IndexedValuesByField<I,CategoricalStats<T>,F> {
        var rv = IndexedValuesByField<I,CategoricalStats<T>,F>(fields: self.fields)
        
        // we need at least one date to extract and one date of data, else we'll return empty
        // last date should be past the last date (+10 seconds) so it's included
        if var indexExtract = ExtractIndexes(extractIndexes: extractIndexes,
                                             start: start,
                                             end: end) {
            
            var current : [F:CategoricalStats<T>] = [:]
            
            for (row,index) in self.indexes.enumerated() {
                indexExtract.looking(at: index)
                
                if indexExtract.beforeStart {
                    continue
                }
                
                if indexExtract.afterEnd {
                    break
                }
                
                if indexExtract.reachedNext {
                    do {
                        try rv.append(fieldsValues: current, for: indexExtract.currentExtractIndex)
                    }catch{
                        throw error
                    }
                    current = [:]
                    indexExtract.next()
                }
                
                if current.count == 0 {
                    //current = zip(self.fields,one).map { C(field: $0, value: $1) }
                    for (field,fieldValues) in self.values {
                        current[field] = CategoricalStats<T>(value:fieldValues[row])
                    }
                }else{
                    for (field,fieldValues) in self.values {
                        current[field]?.update(value: fieldValues[row])
                    }
                }
            }
            // add last one if still there
            if current.count > 0 {
                do {
                    try rv.append(fieldsValues: current, for: indexExtract.currentExtractIndex)
                }catch{
                    throw error
                }
            }
        }
        return rv
    }
    
}
