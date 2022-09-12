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
        return field.numberWithUnit(valueStats: valueStats)?.description ?? ""
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
    func numberWithUnit(baro inch : ValueStats) -> GCNumberWithUnit {
        let val = GCNumberWithUnit(unit: inch.unit, andValue: inch.end)
        return val
    }

    func numberWithUnit(fpm : ValueStats) -> GCNumberWithUnit {
        return GCNumberWithUnit(unit: fpm.unit, andValue: fpm.average)
    }

    func numberWithUnit(degree : ValueStats) -> GCNumberWithUnit {
        if degree.average > 0 {
            return GCNumberWithUnit(unit: degree.unit, andValue: degree.average)
        }else{
            return GCNumberWithUnit(unit: degree.unit, andValue: degree.average+360.0)
        }
    }
    
    func numberWithUnit(gallon : ValueStats, used : Bool = true) -> GCNumberWithUnit {
        if used {
            return GCNumberWithUnit(unit: gallon.unit, andValue: gallon.max-gallon.min)
        }else{
            return GCNumberWithUnit(unit: gallon.unit, andValue: gallon.end)
        }
    }
    
    func numberWithUnit(distance: ValueStats, total : Bool = false) -> GCNumberWithUnit {
        return GCNumberWithUnit(unit: distance.unit, andValue: distance.end)
    }
    
    func numberWithUnit(autopilot : ValueStats) -> GCNumberWithUnit {
        return GCNumberWithUnit(unit: GCUnit.dimensionless(), andValue: autopilot.end)
    }
    func numberWithUnit(engineTemp : ValueStats) -> GCNumberWithUnit {
        return GCNumberWithUnit(unit: engineTemp.unit, andValue: engineTemp.max)
    }
    func numberWithUnit(map: ValueStats) -> GCNumberWithUnit {
        return GCNumberWithUnit(unit: map.unit, andValue: map.average)
    }
    func numberWithUnit(gph : ValueStats) -> GCNumberWithUnit {
        return GCNumberWithUnit(unit: gph.unit, andValue: gph.average)
    }
    func numberWithUnit(speed : ValueStats) -> GCNumberWithUnit {
        return GCNumberWithUnit(unit: speed.unit, andValue: speed.average)
    }
    func numberWithUnit(altitude : ValueStats) -> GCNumberWithUnit {
        return GCNumberWithUnit(unit: altitude.unit, andValue: altitude.max)
    }
    func numberWithUnit(percent : ValueStats) -> GCNumberWithUnit {
        return GCNumberWithUnit(unit: percent.unit, andValue: percent.average)
    }

    func numberWithUnit(frequency : ValueStats) -> GCNumberWithUnit {
        return GCNumberWithUnit(unit: frequency.unit, andValue: frequency.end)
    }
    // default
    func numberWithUnit(_ stat : ValueStats) -> GCNumberWithUnit {
        return GCNumberWithUnit(unit: stat.unit, andValue: stat.average)
    }

}


