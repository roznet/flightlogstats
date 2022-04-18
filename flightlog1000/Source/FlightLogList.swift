//
//  FlightLogList.swift
//  connectflight
//
//  Created by Brice Rosenzweig on 27/06/2021.
//

import Foundation

class FlightLogList {
    
    let directory : URL
    var flightLogs : [FlightLog]
    
    
    init(directory : URL) {
        self.directory = directory
        var logs : [FlightLog] = []
        if let fileURLs = try? FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: []){
            for fileURL in fileURLs {
                if fileURL.pathExtension == "csv" && fileURL.lastPathComponent.hasPrefix("log_"){
                    if let one = try? FlightLog(url: fileURL) {
                        logs.append(one)
                    }
                }
            }
        }
        self.flightLogs = logs
    }
}
