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

struct DisplayedValue {
    enum Formatter {
        case measurement(MeasurementFormatter)
        case compound(CompoundMeasurementFormatter<Dimension>)
        case date(DateFormatter)
    }
    
    let measurement : Measurement<Dimension>
    let formatter : Formatter
    
    var measurementFormatter : MeasurementFormatter? { guard case let .measurement(rv) = self.formatter else { return nil }; return rv }
    var compoundFormatter : CompoundMeasurementFormatter<Dimension>? { guard case let .compound(rv) = self.formatter else { return nil }; return rv }
}

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

    // configurable
    var baroUnit : UnitPressure = UnitPressure.hectopascals
    var temperatureUnit : UnitTemperature = UnitTemperature.celsius
    
    init() {
        self.timeFormatter = DateFormatter()
        self.timeFormatter.dateStyle = .none
        self.timeFormatter.timeStyle = .short
        
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateStyle = .medium
        self.dateFormatter.timeStyle = .none
    }
    
    //MARK: - format model objets

    @available(*, deprecated, message: "Use measurement and formatter")
    func formatDecimal(timeRange : TimeRange) -> String {
        return Self.decimalFormatter.string(from: NSNumber(floatLiteral: timeRange.elapsed/3600.0)) ?? ""
    }
    
    @available(*, deprecated, message: "Use measurement and formatter")
    func formatHHMM(interval : TimeInterval) -> String {
        let formatter = Self.coumpoundHHMMFormatter
        return formatter.format(from: Measurement(value: interval, unit: UnitDuration.seconds))
    }
    
    
    @available(*, deprecated, message: "Use measurement and formatter")
    func formatHHMM(timeRange : TimeRange) -> String {
        let formatter = Self.coumpoundHHMMFormatter
        return formatter.format(from: timeRange.measurement)
    }
    
    //MARK: - Categorical/string formatting
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
    @available(*, deprecated, message: "Use measurement and formatter")
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

    @available(*, deprecated, message: "Use measurement and formatter")
    func format(date : Date) -> String {
        return self.dateFormatter.string(from: date)
    }

    @available(*, deprecated, message: "Use measurement and formatter")
    func formatStats(field : Field, valueStats : ValueStats) -> String {
        let formatter = self.measurementFormatter(for: field)
        if let measurement = self.measurement(field: field, valueStats: valueStats) {
            return formatter.string(from: measurement)
        }
        return ""
    }

    //MARK: - Format ValueStats for Fields
    func measurementOld(field : Field, valueStats : ValueStats) -> Measurement<Dimension>? {
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
    
    func measurement(field : Field, valueStats : ValueStats) -> Measurement<Dimension>? {
        let metric = self.valueStatsMetric(for: field)
        var measurement = valueStats.measurement(for: metric)
        if let displayUnit = self.displayUnit(for: field) {
            measurement?.convert(to: displayUnit)
        }
        return measurement
    }

    
    //MARK: - format values
    func formatValue(distance : Measurement<Dimension>) -> String {
        return Self.defaultFormatter.string(from: distance)
    }

    func formatValue(numberWithUnit : GCNumberWithUnit, converted to: GCUnit? = nil) -> String {
        if let to = to {
            return numberWithUnit.convert(to: to).description
        }
        return numberWithUnit.description
    }
    
    func formatValue(gallon : Measurement<Dimension>) -> String {
        
        return Self.fuelFormatter.string(from: gallon)
    }
    
    //MARK: - Formatters
    
    public static let enduranceFormatter : MeasurementFormatter = {
        let rv = MeasurementFormatter()
        rv.numberFormatter.minimumFractionDigits = 1
        rv.numberFormatter.maximumFractionDigits = 1
        rv.unitOptions = .providedUnit
        return rv
    }()
    
    public static let decimalFormatter : NumberFormatter = {
        let rv = NumberFormatter()
        rv.maximumFractionDigits = 1
        rv.minimumFractionDigits = 1
        return rv
    }()
    
    public static let coumpoundHHMMFormatter :  CompoundMeasurementFormatter<Dimension> = {
        var rv = CompoundMeasurementFormatter<Dimension>(dimensions: [UnitDuration.hours, UnitDuration.minutes, UnitDuration.seconds], separator: ":")
        rv.joinStyle = .noUnits
        rv.numberFormatter.minimumIntegerDigits = 2
        rv.numberFormatter.maximumFractionDigits = 0
        rv.minimumComponents = 2
        return rv
    }()

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
        case .FQtyL,.FQtyR,.FQtyT,.FTotalizerT,.E1_FFlow,.E2_FFlow:
            return Self.fuelFormatter
        case .E1_MAP,.E2_MAP:
            return Self.mapFormatter
        default:
            return Self.defaultFormatter
        }
    }
    
    //MARK: - format stats
    func valueStatsMetric(for field : Field) -> ValueStats.Metric {
        switch field {
        case .AltInd,.AltGPS,.AltMSL:
            return .max
        case .BaroA:
            return .average
        case .OAT:
            return .average
        case .IAS,.GndSpd,.VSpd,.TAS:
            return .average
        case .WndSpd:
            return .average
        case .Pitch,.Roll:
            return .average
        case .LatAc,.NormAc:
            return .max
        case .HDG,.TRK,.CRS:
            return .average
        case .volt1,.volt2,.amp1:
            return .average
        case .FQtyL,.FQtyR,.FQtyT,.FTotalizerT:
            // could be .max-.min
            return .end
        case .E1_FFlow,.E2_FFlow:
            return .average
        case .E1_OilT,.E1_OilP:
            return .average
        case .E1_MAP,.E2_MAP:
            return .average
        case .E1_RPM,.E2_RPM:
            return .average
        case .E1_PctPwr:
            return .average
        case .E1_CHT1,.E1_CHT2,.E1_CHT3,.E1_CHT4,.E1_CHT5,.E1_CHT6:
            return .max
        case .E1_EGT1,.E1_EGT2,.E1_EGT3,.E1_EGT4,.E1_EGT5,.E1_EGT6:
            return .max
        case .E1_TIT1,.E1_TIT2:
            return .max
        case .E1_Torq,.E1_NG,.E2_Torq,.E2_NG:
            return .average
        case .E1_ITT,.E2_ITT:
            return .max
        case .HSIS,.HCDI,.VCDI:
            return .average
        case .WndDr:
            return .average
        case .WptDst:
            return .end
        case .WptBrg,.MagVar:
            return .average
        case .RollM,.PitchM,.RollC,.PichC:
            return .average
        case .VSpdG,.GPSfix,.HAL,.VAL,.HPLwas,.HPLfd,.VPLwas:
            return .average
        
        // Calculated
        case .Distance:
            return .end
        case .WndCross,.WndDirect:
            return .average
        case .E1_EGT_Max,.E1_CHT_Max:
            return .max
        case .E1_EGT_Min,.E1_CHT_Min:
            return .max
        case .Latitude:
            return .start
        case .Longitude:
            return .start
            
        // Not numbers:
        case .Unknown:
            return .start
        case .AtvWpt:
            return .start
        case .NAV1,.NAV2,.COM1,.COM2:
            return .start
        case .UTCOfst, .FltPhase,.Coordinate,.Lcl_Date, .Lcl_Time, .E1_EGT_MaxIdx, .E1_CHT_MaxIdx,.AfcsOn:
            return .start
        }
    }

    func displayUnit(for field : Field) -> Dimension? {
        switch field {
        case .AltInd,.AltGPS,.AltMSL:
            return UnitLength.feet
        case .BaroA:
            return self.baroUnit
        case .OAT:
            return self.temperatureUnit
        case .IAS,.GndSpd,.VSpd,.TAS,.WndSpd:
            return UnitSpeed.knots
        case .Pitch,.Roll,.HDG,.TRK,.CRS:
            return UnitAngle.degrees
        case .WndDr,.WptBrg:
            return UnitAngle.degrees
        case .WptDst:
            return UnitLength.nauticalMiles
        case .LatAc,.NormAc:
            return nil
        case .amp1:
            return UnitElectricCurrent.amperes
        case .volt1,.volt2:
            return UnitElectricPotentialDifference.volts
        case .FQtyL,.FQtyR,.FQtyT,.FTotalizerT:
            // could be .max-.min
            return UnitVolume.aviationGallon
        case .E1_FFlow,.E2_FFlow:
            return UnitFuelFlow.gallonPerHour
        case .E1_OilT:
            return UnitTemperature.fahrenheit
        case .E1_OilP:
            return UnitPressure.poundsForcePerSquareInch
        case .E1_MAP,.E2_MAP:
            return UnitPressure.inchesOfMercury
        case .E1_RPM,.E2_RPM:
            return UnitAngularVelocity.revolutionsPerMinute
        case .E1_PctPwr:
            return UnitPercent.percentPerHundred
        case .E1_CHT1,.E1_CHT2,.E1_CHT3,.E1_CHT4,.E1_CHT5,.E1_CHT6:
            return UnitTemperature.fahrenheit
        case .E1_EGT1,.E1_EGT2,.E1_EGT3,.E1_EGT4,.E1_EGT5,.E1_EGT6:
            return UnitTemperature.fahrenheit
        case .E1_TIT1,.E1_TIT2:
            return UnitTemperature.fahrenheit
        case .E1_Torq,.E2_Torq:
            return UnitEnergy.footPound
        case .E2_NG,.E1_NG:
            return UnitPercent.percentPerHundred
        case .E1_ITT,.E2_ITT:
            return UnitTemperature.celsius
        case .HSIS,.HCDI,.VCDI:
            return UnitAngle.degrees
        case .MagVar:
            return UnitAngle.degrees
        case .RollC,.PichC:
            return UnitAngle.degrees
        case .RollM,.PitchM:
            return nil
        case .VSpdG,.GPSfix,.HAL,.VAL,.HPLwas,.HPLfd,.VPLwas:
            return UnitDimensionLess.scalar
        
        // Calculated
        case .Distance:
            return UnitLength.nauticalMiles
        case .WndCross,.WndDirect:
            return UnitSpeed.knots
        case .E1_EGT_Max,.E1_CHT_Max:
            return UnitTemperature.fahrenheit
        case .E1_EGT_Min,.E1_CHT_Min:
            return UnitTemperature.fahrenheit
        case .Latitude:
            return nil
        case .Longitude:
            return nil
            
        // Not numbers:
        case .Unknown:
            return nil
        case .AtvWpt,.NAV1,.NAV2,.COM1,.COM2:
            return nil
        case .UTCOfst, .FltPhase,.Coordinate,.Lcl_Date, .Lcl_Time, .E1_EGT_MaxIdx, .E1_CHT_MaxIdx,.AfcsOn:
            return nil
        }
    }

    func measurement(_ valueStats : ValueStats) -> Measurement<Dimension> {
        return Measurement(value: valueStats.average, unit: UnitDimensionLess.scalar)
    }
    
    func measurement(baro inch : ValueStats) -> Measurement<Dimension> {
        let unit = (inch.unit as? UnitPressure) ?? UnitPressure.inchesOfMercury
        return Measurement(value: inch.end, unit: unit).converted(to: self.baroUnit)
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
        let unit = (gallon.unit as? UnitVolume) ?? UnitVolume.aviationGallon
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
        let unit = (gph.unit as? UnitVolume) ?? UnitVolume.aviationGallon
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
        return Measurement(value: percent.average, unit: unit).converted(to: UnitPercent.percentPerHundred)
    }
}


