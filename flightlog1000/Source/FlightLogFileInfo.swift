//
//  FlightLogFileInfo.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 24/04/2022.
//

import UIKit
import CoreData
import OSLog

extension Notification.Name {
    static let logFileInfoUpdated : Notification.Name = Notification.Name("Notification.Name.logFileInfoUpdated")
}

class FlightLogFileInfo: NSManagedObject {
    enum FlightLogFileInfoError : Error {
        case invalidFlightLog
    }
    
    enum InfoStatus : String {
        case notParsed
        case parsed
        case empty
        case error
    }
    
    weak var container : FlightLogOrganizer? = nil
    
    /*private*/ var flightLog : FlightLogFile? = nil {
        didSet {
            if let fromLog = self.flightLog?.flightSummary {
                self.flightSummary = fromLog
                self.infoStatus = .parsed
            }
        }
    }
    var infoStatus : InfoStatus {
        get {
            if let status = self.info_status {
                if let rv = InfoStatus(rawValue: status ) {
                    return rv
                }else{
                    return .notParsed
                }
            } else {
                return .notParsed
            }
        }
        set { self.info_status = newValue.rawValue }
    }
    
    lazy var flightSummary : FlightSummary? = FlightSummary(info: self)
    
    static let currentVersion : Int32 = 1
    
    var requiresVersionUpdate : Bool { return self.version < Self.currentVersion }
    var requiresParsing : Bool { return self.requiresVersionUpdate || self.infoStatus == .notParsed }
    
    //MARK: - database utilities
    func delete() {
        if let log = self.flightLog,
           FileManager.default.fileExists(atPath: log.url.path){
            do {
                try FileManager.default.removeItem(at: log.url)
                self.flightLog = nil
            }catch{
                Logger.app.error("Failed to delete \(log.url.path)")
            }
        }
    }
    
    func parseAndUpdate(progress : ProgressReport? = nil) {
        if flightLog == nil {
            guard let container = self.container,
                  let log_file_name = self.log_file_name
            else { return }
            self.flightLog = container.flightLogFile(name: log_file_name)
        }
        
        if let flightLog = flightLog {
            flightLog.parse(progress:progress)
            do {
                try self.updateFromFlightLog(flightLog: flightLog)
                container?.saveContext()
            }catch{
                Logger.app.error("Failed to update \(error.localizedDescription)")
            }
        }
    }
    
    //MARK: - get require data from files
    func updateFromFlightLog(flightLog : FlightLogFile) throws {
        self.flightLog = flightLog

        self.log_file_name = flightLog.name
        
        guard let flightSummary = flightLog.flightSummary else {
            self.infoStatus = .error
            throw FlightLogFileInfoError.invalidFlightLog
        }
        // start empty
        self.infoStatus = .empty
        
        if let system_id = flightLog.meta(key: .system_id) {
            self.system_id = system_id
        }
            
        if let airframe_name = flightLog.meta(key: .airframe_name) {
            self.airframe_name = airframe_name
        }

        if let hobbs = flightSummary.hobbs {
            self.start_time = hobbs.start
            self.end_time = hobbs.end
            // if we have some times, then consider it parsed
            self.infoStatus = .parsed
        }
        
        if let moving = flightSummary.moving {
            self.start_time_moving = moving.start
            self.end_time_moving = moving.end
        }
        
        if let flying = flightSummary.flying {
            self.start_time_flying = flying.start
            self.end_time_flying = flying.end
        }

        self.start_fuel_quantity_left = flightSummary.fuelStart.left
        self.start_fuel_quantity_right = flightSummary.fuelStart.right
        self.end_fuel_quantity_left = flightSummary.fuelEnd.left
        self.end_fuel_quantity_right = flightSummary.fuelEnd.right
        
        self.route = flightSummary.route.map { $0.name }.joined(separator: ",")
        
        self.start_airport_icao = flightSummary.startAirport?.icao
        self.end_airport_icao = flightSummary.endAirport?.icao
        
        self.total_distance = flightSummary.distance
        
        self.version = FlightLogFileInfo.currentVersion
        
    }

    
    func populate(for url : URL){
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "log_yyMMMdd_HHmmss_"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        if let start = dateFormatter.date(from: url.lastPathComponent) {
            self.start_time = start
        }
        if FileManager.default.fileExists(atPath: url.path),
           let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
           let endDate = attr[FileAttributeKey.modificationDate] as? Date {
            self.end_time = endDate
        }
    }
    
    var totalFuelDescription : String {
        guard self.requiresVersionUpdate else { return "??" }
        
        let end_fuel_r = self.end_fuel_quantity_right
        let end_fuel_l = self.end_fuel_quantity_left
        let start_fuel_r = self.start_fuel_quantity_right
        let start_fuel_l = self.start_fuel_quantity_left
        let total = (start_fuel_r+start_fuel_l) - (end_fuel_l+end_fuel_r)
        return String(format: "%.1f gal", total)
    }

}
