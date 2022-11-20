//
//  GroupBy.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 19/11/2022.
//

import Foundation

extension IndexedValuesByField  {
    
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
        if let firstExtractIndex = extractIndexes.first,
           let lastIndex = end ?? self.indexes.last {
            // remove first from extractDates because we already collected it in firstExtractDate
            var remainingIndexes = extractIndexes.dropFirst()
            
            var nextExtractIndex : I = remainingIndexes.first ?? lastIndex
            if remainingIndexes.count > 0 {
                remainingIndexes.removeFirst()
            }
            
            let startIndex = start ?? firstExtractIndex
            let firstIndex = Swift.max(startIndex,firstExtractIndex)
            
            var current : [F:C] = [:]
            var currentExtractIndex = startIndex
            
            for (row,index) in self.indexes.enumerated() {
                let include = index >= firstIndex

                if index > lastIndex {
                    break
                }
                
                if index > nextExtractIndex {
                    if include {
                        do {
                            try rv.append(fieldsValues: current, for: currentExtractIndex)
                        }catch{
                            throw error
                        }
                    }
                    current = [:]
                    currentExtractIndex = nextExtractIndex
                    nextExtractIndex = remainingIndexes.first ?? lastIndex
                    if remainingIndexes.count > 0 {
                        remainingIndexes.removeFirst()
                    }
                }
                if include {
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
            }
            // add last one if still there
            if current.count > 0 {
                do {
                    try rv.append(fieldsValues: current, for: currentExtractIndex)
                }catch{
                    throw error
                }

            }
        }
        return rv
    }

}
