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
        case quickParsed
        case parsed
        case empty
        case error(FlightLogFileError)
    }
    
    private(set) var logType : LogType
    
    let url : URL 
    /// name of the file, typically of the form log_YYYYMMDD_HHmmss.csv
    var name : String { return url.lastPathComponent }
    
    var count : Int { return self.data?.count ?? 0 }
    
    var description : String { return "<FlightLog:\(name)>" }
    
    var requiresParsing : Bool {
        switch self.logType {
        case .notParsed,.quickParsed:
            return true
        case .parsed,.empty,.error:
            return false
        }
    }
    var isParsed : Bool {
        switch self.logType {
        case .notParsed,.quickParsed:
            return false
        case .parsed,.empty,.error:
            return true
        }
    }
    
    var flightSummary : FlightSummary? = nil
    // legs populated in parse
    var legs : [ FlightLeg ] = []

    private var data : FlightData? = nil

    init?(url : URL) {
        if url.lastPathComponent.isFlightLogFile {
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
    
    func quickParse(progress : ProgressReport? = nil) {
        if self.logType == .notParsed {
            // read and process every 5 min
            if let data = FlightData(url: self.url, maxLineCount: nil, lineSamplingFrequency: 60*5, progress: progress) {
                do {
                    self.data = data
                    self.flightSummary = try FlightSummary(data: data)
                    self.logType = .quickParsed
                }catch{
                    self.logType = .error(.parsingError)
                    Logger.app.error("Failed to parse log file \(self.url.lastPathComponent) \(error)")
                }
            }else{
                self.logType = .empty
            }
        }
    }
    
    func parse(progress : ProgressReport? = nil) {
        if self.requiresParsing {
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
                    Logger.app.error("Failed to parse log file \(self.url.lastPathComponent) \(error)")
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
        return self.legs(byfields: [.FltPhase])
    }
    
    func meta(key : MetaField) -> String? {
        return self.data?.meta[key]
    }
    
    func legs(interval : TimeInterval) -> [FlightLeg] {
        var rv : [FlightLeg] = []
        if let flyingStart = self.flightSummary?.flying?.start, let data = self.data {
            rv = FlightLeg.legs(from: data, interval: interval, start: flyingStart)
        }
        return rv
    }
    
    func legs(byfields : [Field]) -> [FlightLeg] {
        // byfields examples:
        //    [.FltPhase] phases of flights
        //    [.AfcsOn,.RollM,.PitchM] auto pilot settings
        //rv = FlightLeg.legs(from: data, interval: 60.0*5.0, start: flyingStart)

        var rv : [FlightLeg] = []
        if let flyingStart = self.flightSummary?.flying?.start, let data = self.data {
            rv = FlightLeg.legs(from: data, byfields:  byfields, start: flyingStart, end: data.lastDate)
        }
        return rv
    }
    
    
    func route(start : Date? = nil) -> [ FlightLeg ] {
        var rv : [FlightLeg] = []
        
        // first identify list of way points
        if let data = self.data {
            rv = FlightLeg.legs(from: data, byfields: [.AtvWpt], start: start, end: data.lastDate)
        }
        
        return rv
    }
    
    func dataSerie(fields : [Field]) -> [Field:GCStatsDataSerie] {
        if let data = self.data {
            let values = data.doubleDataFrame(for: fields)
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
