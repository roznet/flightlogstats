//
//  FlightLogList.swift
//  connectflight
//
//  Created by Brice Rosenzweig on 27/06/2021.
//

import Foundation
import RZUtils
import RZUtilsSwift
import OSLog

class FlightLogFileList {
    private(set) var flightLogFiles : [FlightLogFile]
    
    var description : String {
        return "<FlightLogFileList:\(flightLogFiles.count)>"
    }
    
    var urls : [URL] { return self.flightLogFiles.map { $0.url } }
        
    var first : FlightLogFile? { return self.flightLogFiles.first }
    
    var count : Int { return urls.count }
    
    func dropFirst() {
        self.flightLogFiles = Array(self.flightLogFiles.dropFirst())
    }
    
    init(logs : [FlightLogFile] ) {
        self.flightLogFiles = logs
        self.flightLogFiles.sort { $0.name > $1.name }
    }
    
    init(urls : [URL] ){
        self.flightLogFiles = urls.compactMap { return FlightLogFile(url: $0) }
        self.flightLogFiles.sort { $0.name > $1.name }
    }
    
    @available(*, deprecated, message: "Use logic in organizer")
    func missing(from : FlightLogFileList) -> FlightLogFileList {
        let thisSet = Set<String>(self.flightLogFiles.map { return $0.name })
        var done = Set<String>()
        
        var logs : [FlightLogFile] = []
        for log in from.flightLogFiles {
            if !thisSet.contains(log.name) {
                if done.contains(log.name){
                    Logger.app.warning("Duplicate log name \(log.name)")
                }else{
                    logs.append(log)
                    done.insert(log.name)
                }
            }
        }
        return FlightLogFileList(logs: logs)
    }
    
    @available(*, deprecated, message: "Use logic in organizer")
    func copyMissing(to destFolder : URL) -> Bool {
        var someNew : Bool = false
        for log in self.flightLogFiles {
            let file = log.url
            let dest = destFolder.appendingPathComponent(file.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) {
                do {
                    try FileManager.default.copyItem(at: file, to: dest)
                    Logger.app.info("copied \(file.lastPathComponent) to \(dest)")
                    someNew = true
                } catch {
                    Logger.app.error("failed to copy \(file.lastPathComponent) to \(dest) \(error)")
                }
            }else{
                Logger.app.info("Already copied \(file.lastPathComponent)")
            }
        }
        return someNew
    }
    
}
