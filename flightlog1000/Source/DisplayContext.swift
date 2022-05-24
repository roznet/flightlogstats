//
//  DisplayContext.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 08/05/2022.
//

import Foundation
import CoreLocation
import RZUtils

class DisplayContext {
    typealias Field = FlightLogFile.Field
    enum Style {
        case value
        case range
    }
    
    enum DateStyle {
        case absolute
        case elapsed
        case reference
    }
    
    var style : Style = .value
    var dateStyle : DateStyle = .reference
    var timeFormatter : DateFormatter

    init() {
        self.timeFormatter = DateFormatter()
        self.timeFormatter.dateStyle = .none
        self.timeFormatter.timeStyle = .short
    }
    
    //MARK: - format model objets
    func formatDecimal(timeRange : TimeRange) -> String {
        return String(format: "%.1f", timeRange.elapsed / 3600.0 )
    }
    
    func formatHHMM(timeRange : TimeRange) -> String {
        let hours = floor(timeRange.elapsed / 3600.0)
        let minutes = floor((timeRange.elapsed - (hours * 3600.0))/60.0)
        return String(format: "%02.0f:%02.0f", hours,minutes )
    }
    
    func format(route : [Waypoint] ) -> String {
        return route.map { $0.name }.joined(separator: ",")
    }
    
    func format(waypoint : Waypoint, from : Waypoint? = nil) -> String {
        if let from = from {
            return "\(from.name)-\(waypoint.name)"
        }else{
            return "\(waypoint.name)"
        }
    }
    
    /// Format date according to current convention: absolute, elapsed since beg of entity (ex; leg) or elapsed since reference date
    /// - Parameters:
    ///   - date: the date to format
    ///   - since: the beginning of the period that date is relevant, for example in a leg that would be the start the leg
    ///   - reference: This is the reference date of which to compute general elapsed, typically the first date of the log
    /// - Returns: formatted date according to the convention
    func format(date : Date, since : Date? = nil, reference : Date? = nil) -> String {
        switch self.dateStyle {
        case .elapsed:
            if let since = since {
                return self.formatHHMM(timeRange: TimeRange(start: since, end: date))
            }else{
                return self.timeFormatter.string(from: date)
            }
        case .reference:
            if let reference = reference {
                return self.formatHHMM(timeRange: TimeRange(start: reference, end: date))
            }else{
                return self.timeFormatter.string(from: date)
            }
        case .absolute:
            return self.timeFormatter.string(from: date)
        }
    }
    

    //MARK: - format Fields
    func formatStats(field : Field, valueStats : ValueStats) -> String {
        return field.format(valueStats: valueStats, context: self)
    }
    
    //MARK: - format values
    func formatValue(distanceMeter : CLLocationDistance) -> String {
        return String(format: "%.1f nm", distanceMeter / 1852.0)
    }

    func formatValue(gallon : Double) -> String {
        let val = GCNumberWithUnit(GCUnit.from(logFileUnit: "gal"), andValue: gallon)
        return val.description
    }
    
    //MARK: - format stats
    func formatStats(baro inch : ValueStats) -> String {
        let val = GCNumberWithUnit(GCUnit.from(logFileUnit: "inch"), andValue: inch.average)
        return val.description
    }

    func formatStats(fpm : ValueStats) -> String {
        return String(format: "%.0f fpm", fpm.average)
    }

    func formatStats(degree : ValueStats) -> String {
        return String(format: "%.0f deg", degree.average)
    }
    
    func formatStats(gallon : ValueStats) -> String {
        return String(format: "%.1f gal", gallon.max-gallon.min)
    }
    
    func formatStats(distance: ValueStats) -> String {
        return String(format: "%.1f - %.1f", distance.min,distance.max)
    }
    
    
    func formatStats(engineTemp : ValueStats) -> String {
        return String(format: "%.0f - %.0f", engineTemp.min,engineTemp.max)
    }
    func formatStats(map: ValueStats) -> String {
        return String(format: "%.2f", map.average)
    }
    func formatStats(gph : ValueStats) -> String {
        return String(format: "%.1f - %.1f gph", gph.min, gph.max)
    }
    func formatStats(speed : ValueStats) -> String {
        return String(format: "%.0f kt", speed.average)
    }
    func formatStats(altitude : ValueStats) -> String {
         return String(format: "%.0f ft", altitude.average)
    }
    func formatStats(percent : ValueStats) -> String {
        return String(format: "%.0f %", percent.average * 100.0)
    }

    func formatStats(frequency : ValueStats) -> String {
        return String(format: "%.3f", frequency.end)
    }
    // default
    func formatStats(_ stat : ValueStats) -> String {
        return String(format: "%.0f", stat.average)
    }
    func formatStats1(_ stat : ValueStats) -> String {
        return String(format: "%.1f", stat.average)
    }

}


