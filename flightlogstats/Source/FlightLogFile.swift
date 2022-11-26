//
//  FlightLog.swift
//  connectflight (iOS)
//
//  Created by Brice Rosenzweig on 27/06/2021.
//

import Foundation
import OSLog
import RZUtils

public class FlightLogFile {
    enum FlightLogFileError : Error, Comparable {
        case fileDoesNotExist
        case fileIsNotALogFile
        case parsingError
    }
    
    enum LogType : Comparable {
        case notParsed
        case parsed
        case empty
        case error(FlightLogFileError)
    }
    
    private(set) var logType : LogType
    
    let url : URL 
    var name : String { return url.lastPathComponent }
    
    var description : String { return "<FlightLog:\(name)>" }
    
    var requiresParsing : Bool { return self.logType == .notParsed }
    var isParsed : Bool { return self.logType != .notParsed }
    
    var flightSummary : FlightSummary? = nil
    // legs populated in parse
    var legs : [ FlightLeg ] = []

    private var data : FlightData? = nil

    init?(url : URL) {
        if url.lastPathComponent.isLogFile {
            self.logType = .notParsed
            self.url = url
        }else{
            return nil
        }
    }
    
    init(folder : URL, name : String) throws {
        let url = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            self.logType = .notParsed
            self.url = url
        }else{
            throw FlightLogFileError.fileDoesNotExist
        }
    }
        
    func parse(progress : ProgressReport? = nil) {
        if self.logType == .notParsed {
            self.data = FlightData(url: self.url, progress: progress)
            if let data = self.data {
                do {
                    self.flightSummary = try FlightSummary(data: data)
                    var start : Date? = nil
                    if let flyingStart = self.flightSummary?.flying?.start {
                        start = flyingStart
                    }
                    //start = nil
                    self.legs = self.route(start: start)
                    self.logType = .parsed
                }catch{
                    self.logType = .error(.parsingError)
                    Logger.app.error("Failed to parse log file \(self.url.lastPathComponent)")
                }
            }else{
                self.logType = .empty
            }
        }
    }
    
    func clear() {
        self.logType = .notParsed
        self.data = nil
    }
}

//MARK: - interpretation
extension FlightLogFile {
    
    var phasesOfFLight : [FlightLeg] {
        var rv : [FlightLeg] = []
        if let flyingStart = self.flightSummary?.flying?.start, let data = self.data {
            rv = FlightLeg.legs(from: data, start: flyingStart, byfields: [.FltPhase])
        }
        return rv
    }
    
    func meta(key : MetaField) -> String? {
        self.parse()
        return self.data?.meta[key]
    }
    
    func updateFlightLogFileInfo(info : FlightLogFileInfo){
        try? info.updateFromFlightLog(flightLog: self)
    }
    
    func route(start : Date? = nil) -> [ FlightLeg ] {
        var rv : [FlightLeg] = []
        
        // first identify list of way points
        if let data = self.data {
            rv = FlightLeg.legs(from: data, start: start, byfields: [.AtvWpt])
        }
        
        return rv
    }
    
    func dataSerie(fields : [Field]) -> [Field:GCStatsDataSerie] {
        if let data = self.data {
            let values = data.doubleValues(for: fields)
            return values.dataSeries()
        }
        return [:]
    }
    
    var mapOverlayView : FlightDataMapOverlay? {
        if let data = self.data {
            return FlightDataMapOverlay(data: data)
        }else{
            return nil
        }
    }

}
