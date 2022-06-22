//
//  LogDetailViewModel.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 20/06/2022.
//

import Foundation

extension Notification.Name {
    static let flightLogViewModelChanged : Notification.Name = Notification.Name("Notification.Name.logViewModelChanged")
}

class FlightLogViewModel {
    
    let flightLogFileInfo : FlightLogFileInfo
   
    // MARK: - Configurations
    var displayContext : DisplayContext
    var progress : ProgressReport?

    // MARK: Outputs
    var legsDataSource : FlightLegsDataSource? = nil
    var fuelDataSource : FlightSummaryFuelDataSource? = nil
    var timeDataSource : FlightSummaryTimeDataSource? = nil
    
    // MARK: - Setup
    init(fileInfo : FlightLogFileInfo, displayContext : DisplayContext, progress : ProgressReport? = nil){
        self.flightLogFileInfo = fileInfo
        self.progress = progress
        self.displayContext = displayContext
    }

    func isSameLog(as other : FlightLogFileInfo) -> Bool {
        return other.log_file_name == self.flightLogFileInfo.log_file_name
    }
    
    func build() {
        self.flightLogFileInfo.parseAndUpdate(progress: self.progress)
        
        if let summary = self.flightLogFileInfo.flightSummary {
            self.fuelDataSource = FlightSummaryFuelDataSource(flightSummary: summary, displayContext: displayContext)
            self.fuelDataSource?.prepare()
            
            self.timeDataSource = FlightSummaryTimeDataSource(flightSummary: summary, displayContext: displayContext)
            self.timeDataSource?.prepare()
            
            if let legs = self.flightLogFileInfo.flightLog?.legs {
                let legsDataSource = FlightLegsDataSource(legs: legs, displayContext: displayContext)
                self.legsDataSource = legsDataSource
            }else{
                self.legsDataSource = nil
            }
        }
        NotificationCenter.default.post(name: .flightLogViewModelChanged, object: self)
    }
    
}
