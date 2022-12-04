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
import RZData

class DisplayContext {
    typealias Field = FlightLogFile.Field
    typealias SummaryField = FlightSummary.Field
    
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
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        return formatter.string(from: timeRange.measurement.converted(to: UnitDuration.hours))
    }
    
    func formatHHMM(interval : TimeInterval) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        return formatter.string(from: Measurement(value: interval, unit: UnitDuration.seconds) )
    }
    
    func formatHHMM(timeRange : TimeRange) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        return formatter.string(from: timeRange.measurement)
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
        let formatter = self.measurementFormatter(for: field)
        if let measurement = self.measurement(field: field, valueStats: valueStats) {
            return formatter.string(from: measurement)
        }
        return ""
    }

    func measurement(field : Field, valueStats : ValueStats) -> Measurement<Dimension>? {
        switch field {
        case .AltInd:
            return self.measurement(altitude: valueStats)
        case .BaroA:
            return self.measurement(baro: valueStats)
        case .AltMSL:
            return self.measurement(altitude: valueStats)
        case .OAT:
            return self.measurement(valueStats)
        case .IAS:
            return self.measurement(speed: valueStats)
        case .GndSpd:
            return self.measurement(speed: valueStats)
        case .VSpd:
            return self.measurement(fpm: valueStats)
        case .Pitch:
            return self.measurement(valueStats)
        case .Roll:
            return self.measurement(valueStats)
        case .LatAc:
            return self.measurement(valueStats)
        case .NormAc:
            return self.measurement(valueStats)
        case .HDG:
            return self.measurement(degree: valueStats)
        case .TRK:
            return self.measurement(degree: valueStats)
        case .volt1:
            return self.measurement(valueStats)
        case .volt2:
            return self.measurement(valueStats)
        case .amp1:
            return self.measurement(valueStats)
        case .FQtyL:
            return self.measurement(gallon: valueStats)
        case .FQtyR:
            return self.measurement(gallon: valueStats)
        case .E1_FFlow:
            return self.measurement(gph: valueStats)
        case .E1_OilT:
            return self.measurement(valueStats)
        case .E1_OilP:
            return self.measurement(valueStats)
        case .E1_MAP:
            return self.measurement(map: valueStats)
        case .E1_RPM:
            return self.measurement(valueStats)
        case .E1_PctPwr:
            return self.measurement(percent: valueStats)
        case .E1_CHT1,.E1_CHT2,.E1_CHT3,.E1_CHT4,.E1_CHT5,.E1_CHT6:
            return self.measurement(engineTemp: valueStats)
        case .E1_EGT1,.E1_EGT2,.E1_EGT3,.E1_EGT4,.E1_EGT5,.E1_EGT6:
            return self.measurement(engineTemp: valueStats)
        case .E1_TIT1,.E1_TIT2:
            return self.measurement(engineTemp: valueStats)
        case .E1_Torq:
            return self.measurement(valueStats)
        case .E1_NG:
            return self.measurement(valueStats)
        case .E1_ITT:
            return self.measurement(valueStats)
        case .E2_FFlow:
            return self.measurement(gph: valueStats)
        case .E2_MAP:
            return self.measurement(map: valueStats)
        case .E2_RPM:
            return self.measurement(valueStats)
        case .E2_Torq:
            return self.measurement(valueStats)
        case .E2_NG:
            return self.measurement(valueStats)
        case .E2_ITT:
            return self.measurement(valueStats)
        case .AltGPS:
            return self.measurement(altitude: valueStats)
        case .TAS:
            return self.measurement(speed: valueStats)
        case .HSIS:
            return self.measurement(valueStats)
        case .CRS:
            return self.measurement(degree: valueStats)
        case .HCDI:
            return self.measurement(valueStats)
        case .VCDI:
            return self.measurement(valueStats)
        case .WndSpd:
            return self.measurement(speed: valueStats)
        case .WndDr:
            return self.measurement(degree: valueStats)
        case .WptDst:
            return self.measurement(distance: valueStats, total: true)
        case .WptBrg:
            return self.measurement(degree: valueStats)
        case .MagVar:
            return self.measurement(degree: valueStats)
        case .RollM:
            return self.measurement(valueStats)
        case .PitchM:
            return self.measurement(valueStats)
        case .RollC:
            return self.measurement(degree: valueStats)
        case .PichC:
            return self.measurement(degree: valueStats)
        case .VSpdG:
            return self.measurement(fpm: valueStats)
        case .GPSfix:
            return self.measurement(valueStats)
        case .HAL:
            return self.measurement(valueStats)
        case .VAL:
            return self.measurement(valueStats)
        case .HPLwas:
            return self.measurement(valueStats)
        case .HPLfd:
            return self.measurement(valueStats)
        case .VPLwas:
            return self.measurement(valueStats)
        case .Unknown:
            return self.measurement(valueStats)
        case .AtvWpt:
            return self.measurement(valueStats)
        case .Latitude:
            return self.measurement(valueStats)
        case .Longitude:
            return self.measurement(valueStats)
        
        // Calculated
        case .FQtyT:
            return self.measurement(gallon: valueStats, used: false)
        case .Distance:
            return self.measurement(distance: valueStats, total: true)
        case .WndCross:
            return self.measurement(speed: valueStats)
        case .WndDirect:
            return self.measurement(speed: valueStats)
        case .FTotalizerT:
            return self.measurement(gallon: valueStats, used: false)
        case .E1_EGT_Max,.E1_EGT_Min,.E1_CHT_Max,.E1_CHT_Min:
            return self.measurement(engineTemp: valueStats)
        // Not numbers:
        case .NAV1,.NAV2,.COM1,.COM2:
            return nil
        case .UTCOfst, .FltPhase,.Coordinate,.Lcl_Date, .Lcl_Time, .E1_EGT_MaxIdx, .E1_CHT_MaxIdx,.AfcsOn:
            return nil
        }
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
    
    
    private static var defaultFormatter : MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter
    }()
    
    private static var fuelFormatter : MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter
    }()
    
    private static var mapFormatter : MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 2
        return formatter
    }()
    
    func measurementFormatter(for field : Field) -> MeasurementFormatter {
        switch field {
        case .FQtyL,.FQtyR,.FQtyT,.FTotalizerT:
            return Self.fuelFormatter
        case .E1_MAP,.E2_MAP:
            return Self.mapFormatter
        default:
            return Self.defaultFormatter
        }
    }
    
    //MARK: - format stats
    func measurement(_ valueStats : ValueStats) -> Measurement<Dimension> {
        return Measurement(value: valueStats.average, unit: UnitDimensionLess.scalar)
    }
    
    func measurement(baro inch : ValueStats) -> Measurement<Dimension> {
        let unit = (inch.unit as? UnitPressure) ?? UnitPressure.inchesOfMercury
        return Measurement(value: inch.end, unit: unit)
    }

    func measurement(fpm : ValueStats) -> Measurement<Dimension> {
        let unit = (fpm.unit as? UnitSpeed) ?? UnitSpeed.feetPerMinute
        return Measurement(value: fpm.average, unit: unit)
    }

    func measurement(degree : ValueStats) -> Measurement<Dimension>{
        let unit = (degree.unit as? UnitAngle) ?? UnitAngle.degrees
        if degree.average > 0 {
            return Measurement(value: degree.average, unit: unit)
        }else{
            return Measurement(value: degree.average+360, unit: unit)
        }
    }
    
    func measurement(gallon : ValueStats, used : Bool = true) -> Measurement<Dimension> {
        let unit = (gallon.unit as? UnitVolume) ?? UnitVolume.gallons
        if used {
            return Measurement(value: gallon.max - gallon.min, unit: unit)
        }else{
            return Measurement(value: gallon.end, unit: unit)
        }
    }
    
    func measurement(distance: ValueStats, total : Bool = false) -> Measurement<Dimension> {
        let unit = (distance.unit as? UnitLength) ?? UnitLength.nauticalMiles
        return Measurement(value: distance.end, unit: unit)
    }
    
    func measurement(engineTemp : ValueStats) -> Measurement<Dimension> {
        let unit = (engineTemp.unit as? UnitTemperature) ?? UnitTemperature.fahrenheit
        return Measurement(value: engineTemp.max, unit: unit)
    }
    func measurement(map: ValueStats) -> Measurement<Dimension> {
        let unit = (map.unit as? UnitPressure) ?? UnitPressure.inchesOfMercury
        return Measurement(value: map.average, unit: unit)
    }
    func measurement(gph : ValueStats) -> Measurement<Dimension> {
        let unit = (gph.unit as? UnitVolume) ?? UnitVolume.gallons
        return Measurement(value: gph.average, unit: unit)
    }
    func measurement(speed : ValueStats) -> Measurement<Dimension> {
        let unit = (speed.unit as? UnitSpeed) ?? UnitSpeed.knots
        return Measurement(value: speed.average, unit: unit)
    }
    func measurement(altitude : ValueStats) -> Measurement<Dimension> {
        let unit = (altitude.unit as? UnitLength) ?? UnitLength.feet
        return Measurement(value: altitude.max, unit: unit)
    }
    func measurement(percent : ValueStats) -> Measurement<Dimension> {
        let unit = (percent.unit as? UnitPercent) ?? UnitPercent.percentPerOne
        return Measurement(value: percent.average, unit: unit)
    }
}


