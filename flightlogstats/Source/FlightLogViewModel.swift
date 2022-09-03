//
//  LogDetailViewModel.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 20/06/2022.
//

import Foundation
import RZUtils
import RZUtilsUniversal
import OSLog


extension Notification.Name {
    static let flightLogViewModelChanged : Notification.Name = Notification.Name("Notification.Name.logViewModelChanged")
}

class FlightLogViewModel {
    
    let flightLogFileInfo : FlightLogFileInfo
   
    // Every change update state
    private var writeState : Int = 0
    private var buildState : Int = -1

    private func didWrite() {
        self.writeState += 1
    }
    private func didBuild() {
        self.buildState = self.writeState
    }
    var shouldBuild : Bool {
        return self.buildState < self.writeState
    }
    
    private func save() {
        AppDelegate.worker.async {
            self.flightLogFileInfo.ensureFuelRecord()
            if let record = self.flightLogFileInfo.fuel_record {
                record.fuelAnalysisInputs = self.fuelAnalysisInputs
                self.flightLogFileInfo.saveContext()
            }
        }
    }
    
    // MARK: - Utilities
    var progress : ProgressReport?
    
    // MARK: - Configurations and user inputs
    var displayContext : DisplayContext { didSet { self.didWrite() } }
    var aircraft : Aircraft { didSet { if oldValue != self.aircraft { self.didWrite() } } }
    var fuelAnalysisInputs : FuelAnalysis.Inputs { didSet { if oldValue != self.fuelAnalysisInputs { self.didWrite() } } }
    var fuelTargetUnit : GCUnit { didSet { if oldValue != self.fuelTargetUnit { self.didWrite() } } }
    var fuelAddedUnit : GCUnit { didSet { if oldValue != self.fuelAddedUnit { self.didWrite() } } }
    
    // MARK: Outputs
    private(set) var legsDataSource : FlightLegsDataSource? = nil
    private(set) var fuelDataSource : FlightSummaryFuelDataSource? = nil
    private(set) var timeDataSource : FlightSummaryTimeDataSource? = nil
    private(set) var fuelAnalysisDataSource : FuelAnalysisDataSource? = nil
    private(set) var phasesOfFlightDataSource : FlightLegsDataSource? = nil
    
    var fuelMaxTextLabel : String {
        let max = aircraft.fuelMax.convert(to: fuelTargetUnit)
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 0
        if let maxText = formatter.string(from: NSNumber(floatLiteral: max.totalWithUnit.value)) {
            return "max \(maxText)"
        }else{
            return "max ??"
        }
    }
    
    var estimatedTotalizerStart : FuelQuantity? {
        if let rv = self.flightLogFileInfo.estimatedTotalizerStart {
            return min(rv, self.aircraft.fuelMax)
        }
        return nil
    }
    
    // MARK: - Setup
    init(fileInfo : FlightLogFileInfo, displayContext : DisplayContext, progress : ProgressReport? = nil){
        self.flightLogFileInfo = fileInfo
        self.progress = progress
        self.displayContext = displayContext
        self.aircraft = Settings.shared.aircraft
        fileInfo.ensureFuelRecord()
        if let record = fileInfo.fuel_record {
            self.fuelAnalysisInputs = record.fuelAnalysisInputs
        }else{
            self.fuelAnalysisInputs = FuelAnalysis.Inputs(targetFuel: Settings.shared.targetFuel,
                                                          addedfuel: Settings.shared.addedFuel,
                                                          totalizerStartFuel: Settings.shared.totalizerStartFuel)
        }
        
        self.fuelTargetUnit = Settings.shared.unitTargetFuel
        self.fuelAddedUnit = Settings.shared.unitAddedFuel
    }

    func updateForSettings() {
        self.aircraft = Settings.shared.aircraft
        self.fuelTargetUnit = Settings.shared.unitTargetFuel
        self.fuelAddedUnit = Settings.shared.unitAddedFuel

        self.didWrite()
    }
    
    func isSameLog(as other : FlightLogFileInfo) -> Bool {
        return other.log_file_name == self.flightLogFileInfo.log_file_name
    }
    
    func isValid(target : FuelQuantity) -> Bool {
        return true
    }

    func isValid(added : FuelQuantity) -> Bool {
        if let summary = self.flightLogFileInfo.flightSummary {
            let target = added + summary.fuelEnd
            return target >= summary.fuelEnd && target < self.aircraft.fuelMax
        }else{
            return true
        }
    }
    
    func build() {
        if self.shouldBuild {
            self.progress?.update(state: .start, message: .parsingInfo)
            self.flightLogFileInfo.parseAndUpdate(progress: self.progress)
            
            if let summary = self.flightLogFileInfo.flightSummary {
                self.fuelDataSource = FlightSummaryFuelDataSource(flightSummary: summary, displayContext: self.displayContext)
                self.fuelDataSource?.prepare()
                
                self.timeDataSource = FlightSummaryTimeDataSource(flightSummary: summary, displayContext: self.displayContext)
                self.timeDataSource?.prepare()
                
                self.fuelAnalysisDataSource = FuelAnalysisDataSource(flightSummary: summary, flightViewModel: self)
                self.fuelAnalysisDataSource?.prepare()
                
                let legs = self.flightLogFileInfo.legs
                if legs.count > 0 {
                    let legsDataSource = FlightLegsDataSource(legs: legs, displayContext: self.displayContext)
                    self.legsDataSource = legsDataSource
                }else{
                    self.legsDataSource = nil
                }
                if let phases = self.flightLogFileInfo.flightLog?.phasesOfFLight {
                    self.phasesOfFlightDataSource = FlightLegsDataSource(legs: phases, displayContext: self.displayContext)
                }else{
                    self.phasesOfFlightDataSource = nil
                }
            }
            NotificationCenter.default.post(name: .flightLogViewModelChanged, object: self)
            self.save()
            self.didBuild()
        }
        self.progress?.update(state: .complete)
        
    }
    
    func graphDataSerie(field : FlightLogFile.Field) -> GCStatsDataSerie? {
        if self.shouldBuild {
            return nil
        }
        
        let series = self.flightLogFileInfo.dataSerie(fields: [field])
        return series[field]
    }
    
    let colors : [UIColor] = [UIColor.systemBlue, UIColor.systemRed]
    
    func scatterDataSource(fields : [FlightLogFile.Field], leg : FlightLeg? = nil) -> GCSimpleGraphCachedDataSource? {
        if let start = self.flightLogFileInfo.flightSummary?.hobbs?.start,
           let ds = GCSimpleGraphCachedDataSource.graphDataSource(withTitle: "Plot", andXUnit: GCUnitElapsedSince(start)),
           let first = fields.suffix(2).first,
           let last = fields.suffix(2).last {
            ds.xUnit = first.unit
            if let firstSerie = self.graphDataSerie(field: first),
               let lastSerie = self.graphDataSerie(field: last){
                
                GCStatsDataSerie.reduce(toCommonRange: firstSerie, and: lastSerie)
                let xy = GCStatsInterpFunction.xySerieFor(x: firstSerie, andY: lastSerie)
                
                if let data = GCSimpleGraphDataHolder(xy, type:gcGraphType.scatterPlot, color: self.colors.first!, andUnit: last.unit) {
                    ds.add(data)
                }
            }
            ds.title = fields.map { $0.rawValue }.joined(separator: " x ")
            return ds
        }
        return nil
    }
    
    func graphDataSource(fields : [FlightLogFile.Field], leg : FlightLeg? = nil) -> GCSimpleGraphCachedDataSource? {
        var colorIdx = 0
        
        if let start = self.flightLogFileInfo.flightSummary?.hobbs?.start,
           let ds = GCSimpleGraphCachedDataSource.graphDataSource(withTitle: "Plot", andXUnit: GCUnitElapsedSince(start)){
            for field in fields {
                if let serie = self.graphDataSerie(field: field) {
                    let color = colors[colorIdx % colors.count]
                    
                    if let data = GCSimpleGraphDataHolder(serie, type:gcGraphType.graphLine, color: color, andUnit: field.unit) {
                        data.axisForSerie = UInt( colorIdx )
                        if colorIdx == 0, let leg = leg,
                           let gradientSerie = GCStatsDataSerie() {
                            for point in serie {
                                if let point = point as? GCStatsDataPoint,
                                   let date = point.date() {
                                    if date >= leg.start && date <= leg.end {
                                        gradientSerie.add(GCStatsDataPoint(date: date, andValue: 1.0))
                                    }else{
                                        gradientSerie.add(GCStatsDataPoint(date: date, andValue: 0.0))
                                    }
                                }else{
                                    break
                                }
                            }
                            if gradientSerie.count() == serie.count() {
                                data.gradientColors = GCViewGradientColors([ color, color])
                                data.gradientDataSerie = gradientSerie
                                data.gradientColorsFill = GCViewGradientColors([ UIColor.clear, color.withAlphaComponent(0.3)])
                            }
                        }
                        ds.add(data)
                        colorIdx += 1
                    }
                }
            }
            ds.title = fields.map { $0.rawValue }.joined(separator: ", ")
            return ds
        }
        return nil
    }
}
