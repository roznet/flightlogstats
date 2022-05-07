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
    var flightLog : FlightLogFile? = nil
    
    static let currentVersion : Int32 = 1
    
    var isParsed : Bool { return self.version == Self.currentVersion }
    
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
        guard self.isParsed else { return "??" }
        
        let end_fuel_r = self.end_fuel_quantity_right
        let end_fuel_l = self.end_fuel_quantity_left
        let start_fuel_r = self.start_fuel_quantity_right
        let start_fuel_l = self.start_fuel_quantity_left
        let total = (start_fuel_r+start_fuel_l) - (end_fuel_l+end_fuel_r)
        return String(format: "%.1f gal", total)
    }

}
