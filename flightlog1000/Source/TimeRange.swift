//
//  TimeRange.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 07/05/2022.
//

import Foundation

struct TimeRange {
    let start : Date
    let end : Date
    var elapsed : TimeInterval { return end.timeIntervalSince(start) }
    var elapsedAsDecimalHours : String { return String(format: "%.1f", self.elapsed / 3600.0 )}
    var elapsedAsHHMM : String {
        let hours = round(self.elapsed / 3600.0)
        let minutes = round((self.elapsed - (hours * 3600.0))/60.0)
        return String(format: "%02.0f:%02.0f", hours,minutes )
    }
        
    init?(valuesByField : DatesValuesByField<Double,String>?, field : FlightLogFile.Field) {
        guard let start = valuesByField?.first(field: FlightLogFile.field(field))?.date,
           let end = valuesByField?.last(field: FlightLogFile.field(field))?.date else {
            return nil
        }
        self.start = start
        self.end = end
    }
    
    init(start:Date,end:Date){
        self.start = start
        self.end = end
    }
    
}
