//
//  FlightLogFileInfo.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 24/04/2022.
//

import UIKit
import CoreData
import OSLog
import RZUtils

extension Notification.Name {
    static let logFileRecordUpdated : Notification.Name = Notification.Name("Notification.Name.logFileRecordUpdated")
}

class FlightLogFileRecord: NSManagedObject {
    enum FlightLogFileInfoError : Error {
        case invalidFlightLog
    }
    
    enum RecordStatus : String {
        case notParsed
        case parsed
        case quickParsed
        case empty
        case error
    }
    
    weak var organizer : FlightLogOrganizer? = nil
    
    var flightLog : FlightLogFile? = nil {
        didSet {
            if  let flightLog = self.flightLog, let fromLog = flightLog.flightSummary {
                self.flightSummary = fromLog
                switch flightLog.logType {
                case .quickParsed:
                    self.recordStatus = .quickParsed
                case .parsed:
                    self.recordStatus = .parsed
                case .error,.empty,.notParsed:
                    break
                }
            }
        }
    }
    
    var legs : [FlightLeg] { return self.flightLog?.legs ?? [] }
    
    var recordStatus : RecordStatus {
        get {
            if let status = self.info_status {
                if let rv = RecordStatus(rawValue: status ) {
                    return rv
                }else{
                    return .notParsed
                }
            } else {
                return .notParsed
            }
        }
        set {
            self.info_status = newValue.rawValue
        }
    }
    
    lazy var flightSummary : FlightSummary? = FlightSummary(info: self)
    
    static let currentVersion : Int32 = 1
    
    var fuelRecord : FlightFuelRecord {
        self.ensureDependentRecords()
        return self.fuel_record!
    }
    
    var aircraftRecord : AircraftRecord {
        self.ensureDependentRecords()
        return self.aircraft_record!
    }
    
    var requiresVersionUpdate : Bool { return self.version < Self.currentVersion }
    var requiresParsing : Bool {
        if self.requiresVersionUpdate {
            return true
        }
        switch self.recordStatus {
        case .notParsed,.quickParsed:
            return true
        case .empty,.error:
            return false
        case .parsed:
            return false
        }
    }
    
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
    
    func parseAndUpdate(quick: Bool = false, progress : ProgressReport? = nil) {
        if flightLog == nil {
            guard let container = self.organizer,
                  let log_file_name = self.log_file_name
            else { return }
            self.flightLog = container.flightLogFile(name: log_file_name)
        }
        
        if let flightLog = flightLog {
            if quick {
                flightLog.quickParse(progress: progress)
            }else{
                flightLog.parse(progress:progress)
            }
            do {
                try self.updateFromFlightLog(flightLog: flightLog, quick: true)
                self.saveContext()
            }catch{
                Logger.app.error("Failed to update \(error.localizedDescription)")
            }
        }
    }
    
    func saveContext() {
        self.organizer?.saveContext()
    }
    
    //MARK: - get require data from files
    /// Update record from flight log, if quick will just do minimum it can but mark as not done yet
    /// - Parameters:
    ///   - flightLog: file
    ///   - quick: if true assume not complete, will just get max info it can
    func updateFromFlightLog(flightLog : FlightLogFile, quick: Bool = false) throws {
        // don't do quick parsing if was already parsed
        if quick && self.recordStatus == .parsed {
            return
        }
        
        self.flightLog = flightLog

        self.log_file_name = flightLog.name
        
        let startingStatus = self.recordStatus
        
        self.recordStatus = .empty
        
        if let system_id = flightLog.meta(key: .system_id) {
            self.system_id = system_id
        }
            
        if let airframe_name = flightLog.meta(key: .airframe_name) {
            self.airframe_name = airframe_name
        }

        if let flightSummary = flightLog.flightSummary {
            
            if let hobbs = flightSummary.hobbs {
                self.start_time = hobbs.start
                self.end_time = hobbs.end
                // if we have some times, then consider it parsed
                self.recordStatus = quick ? .quickParsed : .parsed
            }
            
            if let moving = flightSummary.moving {
                self.start_time_moving = moving.start
                self.end_time_moving = moving.end
            }else{
                self.start_time_moving = nil
                self.end_time_moving = nil
                
            }
            
            if let flying = flightSummary.flying {
                self.start_time_flying = flying.start
                self.end_time_flying = flying.end
            }else{
                self.start_time_flying = nil
                self.end_time_flying = nil
            }
            
            self.start_fuel_quantity_left = flightSummary.fuelStart.left
            self.start_fuel_quantity_right = flightSummary.fuelStart.right
            self.end_fuel_quantity_left = flightSummary.fuelEnd.left
            self.end_fuel_quantity_right = flightSummary.fuelEnd.right
            self.fuel_totalizer_total = flightSummary.fuelTotalizer.total
            
            self.route = flightSummary.route.map { $0.name }.joined(separator: ",")
            
            self.start_airport_icao = flightSummary.startAirport?.icao
            self.end_airport_icao = flightSummary.endAirport?.icao
            
            self.total_distance = flightSummary.distanceInNm
            self.max_altitude = flightSummary.altitudeInFeet
            
            self.ensureAircraftRecord()
        }else{
            self.recordStatus = .notParsed
        }
        
        self.version = FlightLogFileRecord.currentVersion
        
        if self.recordStatus != startingStatus, let logname = self.log_file_name {
            Logger.app.info("Record for \(logname) changed status \(startingStatus) -> \(self.recordStatus)")
        }
        
    }

    func updateForKnownIssues() -> Bool {
        var rv = false
        if let system_id = self.system_id {
            let noQuotes = system_id.replacingOccurrences(of: "\"", with: "")
            if noQuotes != system_id {
                self.system_id = noQuotes
                rv = true
            }
        }
        if self.ensureAircraftRecord() {
            rv = true
        }
        
        return rv
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
    
    //MARK: - Ensure dependent object

    func ensureDependentRecords(delaySave : Bool = false) {
        var save = false
        
        if self.ensureFlyStoStatus() {
            save = true
        }
        if self.ensureFuelRecord() {
            save = true
        }
        if self.ensureAircraftRecord(){
            save = true
        }
        
        if save && !delaySave {
            self.saveContext()
        }
    }
    
    
    @discardableResult
    private func ensureAircraftRecord() -> Bool {
        if self.aircraft_record == nil, let container = self.organizer {
            if let sysid = self.system_id {
                self.aircraft_record = container.aircraft(systemId: sysid, airframeName: self.airframe_name)
                return true
            }else{
                Logger.app.warning("Unable to create aircraft record as not system_id found")
            }
        }
        return false
    }
    
    private func ensureFlyStoStatus() -> Bool {
        if self.flysto_record == nil,
           let container = self.organizer {
            let context = container.persistentContainer.viewContext
            let status = FlightFlyStoRecord(context: context)
            status.status = .ready
            self.flysto_record = status
            return true
        }
        return false
    }
    
    private func ensureFuelRecord() -> Bool {
        if self.fuel_record == nil,
           let container = self.organizer {
            let context = container.persistentContainer.viewContext
            let record = FlightFuelRecord(context: context)
            // initialise with default
            record.setupFromSettings()
            record.log_file_name = self.log_file_name
            self.fuel_record = record
            return true
        }
        return false
    }
    
    var estimatedTotalizerStart : FuelQuantity? {
        var rv : FuelQuantity? = nil
        if let previous = self.organizer?.flight(preceding: self) {
            rv = previous.nextTotalizerStart
        }
        return rv
    }
    
    var nextTotalizerStart : FuelQuantity? {
        self.ensureDependentRecords()
        if let record = self.fuel_record {
            return record.nextTotalizerStart(for: FuelQuantity(total: self.fuel_totalizer_total, unit: Settings.fuelStoreUnit))
        }
        return nil
    }
    
    //MARK: - Analysis
    func isSameAircraft(as other : FlightLogFileRecord) -> Bool {
        guard
            let thisSystem = self.system_id, let otherSystem = other.system_id
        else {
            return false
        }
        return thisSystem == otherSystem
    }
    
    func isNewer(than other : FlightLogFileRecord) -> Bool {
        if let start = self.start_time, let otherStart = other.start_time {
            return start.compare(otherStart) == .orderedDescending
        }
        return self.log_file_name! > other.log_file_name!
    }
    
    func isOlder(than other : FlightLogFileRecord) -> Bool {
        if let start = self.start_time, let otherStart = other.start_time {
            return start.compare(otherStart) == .orderedAscending
        }
        return self.log_file_name! < other.log_file_name!
    }
    
    func isEarlier(than date : Date) -> Bool {
        if let start = self.start_time {
            return date.compare(start) == .orderedAscending
        }
        return false
    }

    func isLater(than date : Date) -> Bool {
        if let start = self.start_time {
            return date.compare(start) == .orderedDescending
        }
        return false
    }

    var isEmpty : Bool {
        if let elapsed = self.flightSummary?.flying?.elapsed,
           let distance = self.flightSummary?.distanceInNm {
            return elapsed == 0.0 || distance < 0.2
        }
        return true
    }
    
    var isFlight : Bool {
        if self.isEmpty {
            return false
        }
        if let summary = self.flightSummary {
            return summary.summaryType == .flight
        }
        return false
    }
    
    func contains(_ searchText : String ) -> Bool {
        if let summary = self.flightSummary {
            if summary.contains(searchText) {
                return true
            }
        }
        if log_file_name?.contains(searchText) ?? false {
            return true
        }
        if self.aircraftRecord.contains(searchText) {
            return true
        }
        return false
    }
    
    func dataSerie(fields : [FlightLogFile.Field]) -> [FlightLogFile.Field:GCStatsDataSerie] {
        if let flightLog = self.flightLog {
            return flightLog.dataSerie(fields: fields)
        }
        return [:]
    }
}
