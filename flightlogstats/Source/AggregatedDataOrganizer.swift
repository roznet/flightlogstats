//
//  AggregatedDataOrganizer.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 18/02/2023.
//

import Foundation
import OSLog
import RZUtils
import RZUtilsSwift

class AggregatedDataOrganizer {
    private let db : FMDatabase
    
    private(set) var aggregatedData : FlightLogFileAggregatedData
    private var table : String
    private var configTable : String { return "\(table)_config" }
    private let interval : TimeInterval
    
    weak var organizer : FlightLogOrganizer? = nil
    
    convenience init?(databaseName : String = "aggregatedLogs.db", table : String = "logdata") {
        let path = RZFileOrganizer.writeableFilePath(databaseName)
        let db = FMDatabase(path: path)
        db.open()
        self.init(db: db, table: table)
    }
    
    init?(db : FMDatabase, table : String = "logdata"){
        self.db = db
        self.interval = 60.0
        self.table = table
        self.aggregatedData = FlightLogFileAggregatedData(from: db, table: table)
        
        guard self.checkOrInitDb() else { return nil }
    }

    static let currentDatabaseVersion = 1
    /// Check if the database config exists and is compatible or return nil
    /// if the config does not exist, create it with current settings
    private func checkOrInitDb() -> Bool {
        if !db.tableExists(self.configTable) {
            // create if does not exists
            if !db.executeUpdate("CREATE TABLE \(self.configTable) (version INTEGER, interval REAL)", withArgumentsIn: []) {
                let error = db.lastError()
                Logger.app.error("Error creating config table: \(error.localizedDescription)")
                return false
            }
            if !db.executeUpdate("INSERT INTO \(self.configTable) (version,interval) VALUES (?,?)",
                                 withArgumentsIn: [Self.currentDatabaseVersion,self.interval]){
                let error = db.lastError()
                Logger.app.error("Error inserting config table: \(error.localizedDescription)")
                return false
            }
            return true
        }else{
            if let rs = db.executeQuery("SELECT version, interval FROM \(self.configTable) ORDER BY version DESC LIMIT 1", withArgumentsIn: []) {
                if rs.next() {
                    let version = rs.int(forColumn: "version")
                    let interval = rs.double(forColumn: "interval")
                    if version == Self.currentDatabaseVersion && interval.isAlmostEqual(to: self.interval){
                        return true
                    }else{
                        Logger.app.error("Inconsistent database \(version),\(interval)")
                        return false
                    }
                }
            }
        }
        return false
    }
    func insertOrReplace(flightLog : FlightLogFile) {
        do {
            let aggregatedRecord = try FlightLogFileAggregatedData.aggregate(flightLog: flightLog,
                                                                             interval: self.interval,
                                                                             schema: FlightLogFileAggregatedData.defaultSchema)
            // Save to db, it will replace old one if exists already
            aggregatedRecord.save(to: self.db, table: self.table)
            self.aggregatedData.insertOrReplace(data: aggregatedRecord)
        }catch{
            Logger.app.error("Failed to get aggregated data from record \(error)")
        }
    }
    func insertOrReplace(record : FlightLogFileRecord) {
        guard let flightLog = record.flightLog else { return }
        self.insertOrReplace(flightLog: flightLog)
        
    }
}
