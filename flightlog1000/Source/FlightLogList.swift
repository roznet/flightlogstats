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
    
    var description : String {
        return "<FlightLogList:\(directory.lastPathComponent):\(flightLogs.count)>"
    }
    
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
    
    init(cloud : URL){
        
        self.directory = cloud
        self.flightLogs = []
        let query = NSMetadataQuery()
        query.notificationBatchingInterval = 1
        query.searchScopes = [NSMetadataQueryUbiquitousDataScope, NSMetadataQueryUbiquitousDocumentsScope]
        
        //NotificationCenter.default.addObserver(forName: NSMetadataQuery.didfin NSMetadataQueryDidFinishGathering, object: <#T##Any?#>, queue: <#T##OperationQueue?#>, using: <#T##(Notification) -> Void#>)
        
        query.start()
    }
    
    func finishedGathering(query : NSMetadataQuery) {
        
    }
}
