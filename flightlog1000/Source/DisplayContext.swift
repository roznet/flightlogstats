//
//  DisplayContext.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 08/05/2022.
//

import Foundation
import CoreLocation
import RZUtils
import RZFlight
import RZUtilsSwift

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
    
    enum AirportStyle {
        case icaoOnly
        case nameOnly
        case both
    }
    
    var style : Style = .value
    var dateStyle : DateStyle = .reference
    var timeFormatter : DateFormatter
    var dateFormatter : DateFormatter

    init() {
        self.timeFormatter = DateFormatter()
        self.timeFormatter.dateStyle = .none
        self.timeFormatter.timeStyle = .short
        
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateStyle = .medium
        self.dateFormatter.timeStyle = .none
    }
    
    //MARK: - format model objets
    func formatDecimal(timeRange : TimeRange) -> String {
        return timeRange.numberWithUnit.convert(to: GCUnit.decimalhour()).description
    }
    
    func formatHHMM(interval : TimeInterval) -> String {
        return GCNumberWithUnit(unit: GCUnit.second(), andValue: interval).convert(to: GCUnit.hobbshour()).description
    }
    
    func formatHHMM(timeRange : TimeRange) -> String {
        return timeRange.numberWithUnit.convert(to: GCUnit.hobbshour()).description
    }
    
    func format(route : [Waypoint] ) -> String {
        return route.map { $0.name }.joined(separator: ",")
    }
    
    func format(airport : Airport?, style : AirportStyle = .both) -> String {
        if let airport = airport {
            switch style {
            case .both:
                return "\(airport.icao) \(airport.name)"
            case .nameOnly:
                return airport.name
            case .icaoOnly:
                return airport.icao
            }
        }else{
            return ""
        }
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
    func format(time : Date, since : Date? = nil, reference : Date? = nil) -> String {
        switch self.dateStyle {
        case .elapsed:
            if let since = since {
                return self.formatHHMM(timeRange: TimeRange(start: since, end: time))
            }else{
                return self.timeFormatter.string(from: time)
            }
        case .reference:
            if let reference = reference {
                return self.formatHHMM(timeRange: TimeRange(start: reference, end: time))
            }else{
                return self.timeFormatter.string(from: time)
            }
        case .absolute:
            return self.timeFormatter.string(from: time)
        }
    }

    func format(date : Date) -> String {
        return self.dateFormatter.string(from: date)
    }


    //MARK: - format Fields
    func formatStats(field : Field, valueStats : ValueStats) -> String {
        return field.format(valueStats: valueStats, context: self)
    }
    
    //MARK: - NumberWithUnits convert
    func numberWithUnit(gallon : Double) -> GCNumberWithUnit {
        return GCNumberWithUnit(unit: GCUnit.usgallon(), andValue: gallon)
    }
    
    //MARK: - format values
    func formatValue(distance : Double) -> String {
        return String(format: "%.1f nm", distance )
    }

    func formatValue(numberWithUnit : GCNumberWithUnit, converted to: GCUnit? = nil) -> String {
        if let to = to {
            return numberWithUnit.convert(to: to).description
        }
        return numberWithUnit.description
    }
    
    func formatValue(gallon : Double) -> String {
        let val = GCNumberWithUnit(GCUnit.from(logFileUnit: "gals"), andValue: gallon)
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
        if degree.average > 0 {
            return String(format: "%.0f deg", degree.average)
        }else{
            return String(format: "%.0f deg", 360.0 + degree.average)
        }
    }
    
    func formatStats(gallon : ValueStats, used : Bool = true) -> String {
        if used {
            return String(format: "%.1f gal", gallon.max-gallon.min)
        }else{
            return String(format: "%.1f gal", gallon.end)
        }
    }
    
    func formatStats(distance: ValueStats, total : Bool = false) -> String {
        if total {
            return String(format: "%.1f nm", distance.end)
        }else{
            return String(format: "%.1f - %.1f nm", distance.min,distance.max)
        }
    }
    
    func formatStats(autopilot : ValueStats) -> String {
        if autopilot.end == 0 {
            return "Off"
        }else{
            return "On"
        }
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


