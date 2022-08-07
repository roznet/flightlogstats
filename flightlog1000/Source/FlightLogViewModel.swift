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
                                                          addedfuel: Settings.shared.addedFuel)
        }
        
        self.fuelTargetUnit = Settings.shared.unitTargetFuel
        self.fuelAddedUnit = Settings.shared.unitAddedFuel
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
            }
            NotificationCenter.default.post(name: .flightLogViewModelChanged, object: self)
            self.save()
            self.didBuild()
        }
    }
    
    func graphDataSerie(field : FlightLogFile.Field) -> GCStatsDataSerie? {
        if self.shouldBuild {
            return nil
        }
        
        let series = self.flightLogFileInfo.dataSerie(fields: [field])
        return series[field]
    }
    
    func graphDataSource(field : FlightLogFile.Field, leg : FlightLeg? = nil) -> GCSimpleGraphCachedDataSource? {
        if let start = self.flightLogFileInfo.flightSummary?.hobbs?.start,
           let serie = self.graphDataSerie(field: field),
           let ds = GCSimpleGraphCachedDataSource.graphDataSource(withTitle: "Plot", andXUnit: GCUnitElapsedSince(start)) {
            
            if let data = GCSimpleGraphDataHolder(serie, type:gcGraphType.graphLine, color: UIColor.systemBlue, andUnit: field.unit) {
                if let leg = leg,
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
                        data.gradientColors = GCViewGradientColors([ UIColor.systemBlue, UIColor.systemBlue])
                        data.gradientDataSerie = gradientSerie
                        data.gradientColorsFill = GCViewGradientColors([ UIColor.clear, UIColor.systemBlue.withAlphaComponent(0.3)])
                    }
                }
                ds.add(data)
                
            }
            
            return ds
        }
        return nil
    }
}
