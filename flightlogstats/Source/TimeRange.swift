//
//  TimeRange.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 07/05/2022.
//

import Foundation
import RZUtils

struct TimeRange : Codable {
    typealias Field = FlightLogFile.Field
    
    let start : Date
    let end : Date
    var elapsed : TimeInterval { return end.timeIntervalSince(start) }
    
    var numberWithUnit : GCNumberWithUnit { return GCNumberWithUnit(unit: GCUnit.second(), andValue: self.elapsed)}
    
    init?(valuesByField : IndexedValuesByField<Date,Double,Field>?, field : FlightLogFile.Field) {
        guard let start = valuesByField?.first(field: field)?.index,
           let end = valuesByField?.last(field: field)?.index else {
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
    
    func schedule(interval : TimeInterval) -> [Date] {
        let first = Date(timeIntervalSinceReferenceDate: floor(self.start.timeIntervalSinceReferenceDate/interval) * interval )
        let last =  first.addingTimeInterval(ceil(self.end.timeIntervalSince(first)/interval) * interval )
        var rv : [Date] = []
        var date = first
        while date < last {
            rv.append(date)
            date = date.addingTimeInterval(interval)
        }
        rv.append(last)
        return rv
    }
}

extension Array<Date> {
    func regularShedule(interval : TimeInterval) -> [Date] {
        guard let start = self.first, let end = self.last else { return [] }
        
        return TimeRange(start: start, end: end).schedule(interval: interval)
    }
}
