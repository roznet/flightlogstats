//
//  TimeRange.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 07/05/2022.
//

import Foundation

struct TimeRange {
    typealias Field = FlightLogFile.Field
    
    let start : Date
    let end : Date
    var elapsed : TimeInterval { return end.timeIntervalSince(start) }
        
    init?(valuesByField : DatesValuesByField<Double,Field>?, field : FlightLogFile.Field) {
        guard let start = valuesByField?.first(field: field)?.date,
           let end = valuesByField?.last(field: field)?.date else {
            return nil
        }
        self.start = start
        self.end = end
    }
    
    init(start:Date,end:Date){
        self.start = start
        self.end = end
    }
    
    func startTo(start other : TimeRange) -> TimeRange {
        return TimeRange(start: self.start, end: other.start)
    }
    
    func startTo(end other : TimeRange) -> TimeRange {
        return TimeRange(start: self.start, end: other.end)
    }

    
    /// Return new range that start from current end ot the end of other
    /// - Parameter other: other range ot pick end from
    /// - Returns: new range
    func endTo(end other : TimeRange) -> TimeRange {
        return TimeRange(start: self.end, end: other.end)
    }
}
