//
//  LogDetailViewModel.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 20/06/2022.
//

import Foundation
import RZUtils

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
    
    // MARK: - Utilities
    var progress : ProgressReport?
    
    // MARK: - Configurations and user inputs
    var displayContext : DisplayContext { didSet { self.didWrite() } }
    var aircraft : Aircraft { didSet { self.didWrite() } }
    var fuelAnalysisInputs : FuelAnalysis.Inputs { didSet { self.didWrite() } }
    var fuelTargetUnit : GCUnit { didSet { self.didWrite() } }
    var fuelAddedUnit : GCUnit { didSet { self.didWrite() } }

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
        self.aircraft = Aircraft(fuelMax: FuelQuantity(total: 92.0, unit:GCUnit.usgallon()),
                                 fuelTab: FuelQuantity(total: 60.0, unit:GCUnit.usgallon()),
                                 gph: 17.0)
        self.fuelAnalysisInputs = FuelAnalysis.Inputs(targetFuel: FuelQuantity(total: 70.0, unit: GCUnit.usgallon()),
                                                     addedfuel: FuelQuantity(left: 31, right: 29, unit: GCUnit.liter()))
        self.fuelTargetUnit = GCUnit.usgallon()
        self.fuelAddedUnit = GCUnit.liter()
    }

    func isSameLog(as other : FlightLogFileInfo) -> Bool {
        return other.log_file_name == self.flightLogFileInfo.log_file_name
    }
    
    func isValid(target : FuelQuantity) -> Bool {
        if let summary = self.flightLogFileInfo.flightSummary {
            return target >= summary.fuelEnd && target < self.aircraft.fuelMax
        }else{
            return true
        }
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
                
                if let legs = self.flightLogFileInfo.flightLog?.legs {
                    let legsDataSource = FlightLegsDataSource(legs: legs, displayContext: self.displayContext)
                    self.legsDataSource = legsDataSource
                }else{
                    self.legsDataSource = nil
                }
            }
            NotificationCenter.default.post(name: .flightLogViewModelChanged, object: self)
            
            self.didBuild()
        }
    }
    
}
