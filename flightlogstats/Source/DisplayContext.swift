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
    
    enum Value {
        case measurement(Measurement<Dimension>)
        case date(Date)
    }
    
    let formatter : Formatter
    let value : Value
    
    var measurement : Measurement<Dimension>? { guard case let .measurement(rv) = self.value else { return nil }; return rv }
    var date : Date? { guard case let .date(rv) = self.value else { return nil }; return rv }
    
    var measurementFormatter : MeasurementFormatter? { guard case let .measurement(rv) = self.formatter else { return nil }; return rv }
    var compoundFormatter : CompoundMeasurementFormatter<Dimension>? { guard case let .compound(rv) = self.formatter else { return nil }; return rv }
    var dateFormatter : DateFormatter? { guard case let .date(rv) = self.formatter else { return nil }; return rv }
    
    var string : String {
        switch self.formatter {
        case .measurement(let fmt):
            switch self.value {
            case .measurement(let m):
                return fmt.string(from: m)
            case .date(let d):
                return d.description
            }
        case .date(let fmt):
            switch self.value {
            case .measurement(let m):
                return m.description
            case .date(let d):
                return fmt.string(from: d)
            }
        case .compound(let fmt):
            switch self.value {
            case .measurement(let m):
                return fmt.format(from: m)
            case .date(let d):
                return d.description
            }
        }
    }
    typealias CellHolder = TableDataSource.CellHolder
    
    func cellHolder(attributes : [NSAttributedString.Key:Any]) -> CellHolder {
        switch self.formatter {
        case .measurement(let fmt):
            switch self.value {
            case .measurement(let m):
                return CellHolder(measurement: m, formatter: fmt, attributes: attributes)
            case .date(let d):
                return CellHolder(string: d.description, attributes: attributes)
            }
        case .date(let fmt):
            switch self.value {
            case .measurement(let m):
                return CellHolder(string: m.description, attributes: attributes)
            case .date(let d):
                return CellHolder(string: fmt.string(from: d), attributes: attributes)
            }
        case .compound(let fmt):
            switch self.value {
            case .measurement(let m):
                return CellHolder(measurement: m, compound: fmt)
            case .date(let d):
                return CellHolder(string: d.description, attributes: attributes)
            }
        }

    }
    
    func adjust(geometry : RZNumberWithUnitGeometry) {
        guard case let .measurement(measurement) = self.value else { return }
        switch self.formatter {
        case .measurement(let fmt):
            geometry.adjust(measurement: measurement, formatter: fmt)
        case .compound(let cmp):
            geometry.adjust(measurement: measurement, compound: cmp)
        case .date:
            break
        }
    }
    
    
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

    //@available(*, deprecated, message: "Use measurement and formatter")
    func formatDecimal(timeRange : TimeRange) -> String {
        return Self.decimalFormatter.string(from: NSNumber(floatLiteral: timeRange.elapsed/3600.0)) ?? ""
    }
    
    
    //@available(*, deprecated, message: "Use measurement and formatter")
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

    //MARK: - Format ValueStats for Fields
    
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

    public static var defaultFormatter : MeasurementFormatter = {
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
        case .Lcl_Time:
            return Self.enduranceFormatter
        default:
            return Self.defaultFormatter
        }
    }
    
    //MARK: - format stats
    func valueStatsMetric(for field : Field) -> ValueStats.Metric {
        switch field {
        case .AltInd,.AltGPS,.AltMSL,.AltB:
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
        case .E1_FFlow,.E2_FFlow,.E1_FPres,.E2_FPres:
            return .average
        case .E1_OilT,.E1_OilP,.E2_OilP,.E2_OilT:
            return .average
        case .E1_MAP,.E2_MAP:
            return .average
        case .E1_RPM,.E2_RPM:
            return .average
        case .E1_PctPwr,.E2_PctPwr:
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
        case .Distance,.Elapsed:
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
        case .AltInd,.AltGPS,.AltMSL,.AltB:
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
        case .E1_OilT,.E2_OilT:
            return UnitTemperature.fahrenheit
        case .E1_OilP,.E2_OilP:
            return UnitPressure.poundsForcePerSquareInch
        case .E1_MAP,.E2_MAP:
            return UnitPressure.inchesOfMercury
        case .E1_RPM,.E2_RPM:
            return UnitAngularVelocity.revolutionsPerMinute
        case .E1_PctPwr,.E2_PctPwr:
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
        case .E1_FPres,.E2_FPres:
            return UnitPressure.poundsForcePerSquareInch
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
        case .Elapsed:
            return UnitDuration.seconds
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

    func displayedValue(field : Field, measurement : Measurement<Dimension>) -> DisplayedValue {
        var measurement = measurement
        if let preferredUnit = self.displayUnit(for: field) {
            measurement.convert(to: preferredUnit)
        }
        
        switch field {
        case .AltInd,.AltGPS,.AltMSL,.AltB:
             return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .BaroA:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .OAT:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .IAS,.GndSpd,.VSpd,.TAS,.WndSpd:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .Pitch,.Roll,.HDG,.TRK,.CRS:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .WndDr,.WptBrg:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .WptDst:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .LatAc,.NormAc:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .amp1:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .volt1,.volt2:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .FQtyL,.FQtyR,.FQtyT,.FTotalizerT:
            // could be .max-.min
            return DisplayedValue(formatter: .measurement(Self.fuelFormatter), value: .measurement(measurement))
        case .E1_FFlow,.E2_FFlow:
            return DisplayedValue(formatter: .measurement(Self.fuelFormatter), value: .measurement(measurement))
        case .E1_OilT,.E2_OilT:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .E1_OilP,.E2_OilP:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .E1_MAP,.E2_MAP:
            return DisplayedValue(formatter: .measurement(Self.mapFormatter), value: .measurement(measurement))
        case .E1_FPres,.E2_FPres:
            return DisplayedValue(formatter: .measurement(Self.mapFormatter), value: .measurement(measurement))
        case .E1_RPM,.E2_RPM:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .E1_PctPwr,.E2_PctPwr:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .E1_CHT1,.E1_CHT2,.E1_CHT3,.E1_CHT4,.E1_CHT5,.E1_CHT6:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .E1_EGT1,.E1_EGT2,.E1_EGT3,.E1_EGT4,.E1_EGT5,.E1_EGT6:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .E1_TIT1,.E1_TIT2:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .E1_Torq,.E2_Torq:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .E2_NG,.E1_NG:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .E1_ITT,.E2_ITT:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .HSIS,.HCDI,.VCDI:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .MagVar:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .RollC,.PichC:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .RollM,.PitchM:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .VSpdG,.GPSfix,.HAL,.VAL,.HPLwas,.HPLfd,.VPLwas:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        
        // Calculated
        case .Distance:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .Elapsed:
            return DisplayedValue(formatter: .compound(Self.coumpoundHHMMFormatter), value: .measurement(measurement))
        case .WndCross,.WndDirect:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .E1_EGT_Max,.E1_CHT_Max:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .E1_EGT_Min,.E1_CHT_Min:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .Latitude:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .Longitude:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
            
        // Not numbers:
        case .Unknown:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .AtvWpt,.NAV1,.NAV2,.COM1,.COM2:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
        case .UTCOfst, .FltPhase,.Coordinate,.Lcl_Date, .Lcl_Time, .E1_EGT_MaxIdx, .E1_CHT_MaxIdx,.AfcsOn:
            return DisplayedValue(formatter: .measurement(Self.defaultFormatter), value: .measurement(measurement))
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


