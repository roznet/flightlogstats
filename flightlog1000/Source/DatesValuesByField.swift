//
//  TimedDataByField.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 24/04/2022.
//

import Foundation

public struct DatesValuesByField<T,F : Hashable> {
    public enum TimeDataByFieldError : Error {
        case inconsistentDateOrder
        case inconsistentDataSize
        case unknownField
    }
    
    public typealias FieldsValues = [F:T]
    
    public struct DateValue {
        public let date : Date
        public let value : T
    }
    
    public struct DatesValues {
        public let dates : [Date]
        public let values : [T]
        
        public func dropFirst(_ k : Int) -> DatesValues {
            return DatesValues(dates: [Date]( self.dates.dropFirst(k) ), values: [T]( self.values.dropFirst(k)) )
        }
    }
    
    private(set) var dates : [Date]
    private var values : [F:[T]]
    
    var count : Int { return dates.count }
    
    public init(fields : [F]){
        dates = []
        values = [:]
        for field in fields {
            values[field] = []
        }
    }
    
    
    //MARK: - modify, append
    public mutating func append(field : F, element : T, for date : Date) throws {
        if let last = dates.last {
            if date > last {
                dates.append(date)
            }else if date < last {
                throw TimeDataByFieldError.inconsistentDateOrder
            }
        }else{
            // nothing yet, insert date
            dates.append(date)
        }
        guard let dataForField = values[field] else { throw TimeDataByFieldError.inconsistentDataSize }
        if dataForField.count != (dates.count - 1) {
            throw TimeDataByFieldError.inconsistentDataSize
        }
        values[field]!.append(element)
    }
    
    public mutating func append(fields : [F], elements: [T], for date : Date) throws {
        if let last = dates.last {
            if date > last {
                dates.append(date)
            }else if date < last {
                throw TimeDataByFieldError.inconsistentDateOrder
            }
        }else{
            // nothing yet, insert date
            dates.append(date)
        }
        for (field,element) in zip(fields,elements) {
            guard let dataForField = values[field] else { throw TimeDataByFieldError.inconsistentDataSize }
            if dataForField.count != (dates.count - 1) {
                throw TimeDataByFieldError.inconsistentDataSize
            }
            values[field]!.append(element)
        }
    }
    
    public func dropFirst(field : F, minimumMatchCount : Int = 1, matching : ((T) -> Bool)) -> DatesValuesByField? {
        
        guard let fieldValues = self.values[field]
        else {
            return nil
        }
        
        var rv = DatesValuesByField(fields: [F](self.values.keys))

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
            rv.dates = [Date](self.dates.dropFirst(found))
            for (oneField,oneFieldValues) in self.values {
                rv.values[oneField] = [T](oneFieldValues.dropFirst(found))
            }
        }
        return rv
    }
    
    public func dropLast(field : F, matching : ((T) -> Bool)) -> DatesValuesByField? {
        
        guard let fieldValues = self.values[field]
        else {
            return nil
        }
        
        var rv = DatesValuesByField(fields: Array(self.values.keys))

        var found : Int = 0
        for (idx,value) in fieldValues.reversed().enumerated() {
            if matching(value) {
                found = idx
                break
            }
        }

        rv.dates = [Date](self.dates.dropLast(found))
        for (oneField,oneFieldValues) in self.values {
            rv.values[oneField] = [T](oneFieldValues.dropLast(found))
        }
        return rv
    }
    
    //MARK: - access
    public func last(field : F, matching : ((T) -> Bool)? = nil) -> DateValue?{
        guard let fieldValues = self.values[field],
              let lastDate = self.dates.last,
              let lastValue = fieldValues.last
        else {
            return nil
        }
        
        if let matching = matching {
            for (date,value) in zip(dates.reversed(),fieldValues.reversed()) {
                if matching(value) {
                    return DateValue(date: date, value: value)
                }
            }
            return nil
        }else{
            return DateValue(date: lastDate, value: lastValue)
        }
    }

    public func first(field : F, matching : ((T) -> Bool)? = nil) -> DateValue?{
        guard let fieldValues = self.values[field],
              let firstDate = self.dates.first,
              let firstValue = fieldValues.first
        else {
            return nil
        }
        
        if let matching = matching {
            for (date,value) in zip(dates,fieldValues) {
                if matching(value) {
                    return DateValue(date: date, value: value)
                }
            }
            return nil
        }else{
            return DateValue(date: firstDate, value: firstValue)
        }
    }
    
    public func dateValue(for field : F, at index : Int) -> DateValue? {
        guard let fieldValues = self.values[field], index < self.dates.count else { return nil }
        let value = fieldValues[index]
        let date = self.dates[index]
        return DateValue(date: date, value: value)
    }

    public func value(for field : F, at index : Int) -> T? {
        guard let fieldValues = self.values[field], index < self.dates.count else { return nil }
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
    
    public subscript(_ field : F) -> DatesValues? {
        guard let values = self.values[field] else { return nil }
        return DatesValues(dates: self.dates, values: values)
    }
    
}

extension DatesValuesByField  where T == Double, F == FlightLogFile.Field {
    public func valueStats(from : Date, to : Date) -> [F:ValueStats] {
        var rv : [F:ValueStats] = [:]
        var started : Bool = false
        for (idx,runningdate) in self.dates.enumerated(){
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

}
