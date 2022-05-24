//
//  FlightLog.swift
//  connectflight (iOS)
//
//  Created by Brice Rosenzweig on 27/06/2021.
//

import Foundation
import OSLog

class FlightLogFile {
    enum FlightLogFileError : Error {
        case fileDoesNotExist
    }
    
    let url : URL 
    var name : String { return url.lastPathComponent }
    
    var description : String { return "<FlightLog:\(name)>" }
    
    var isParsed : Bool { return data != nil }
    
    var flightSummary : FlightSummary? = nil
    var legs : [ FlightLeg ] = []

    private var data : FlightData? = nil

    init?(url : URL) {
        if url.lastPathComponent.isLogFile {
            self.url = url
        }else{
            return nil
        }
    }
    
    init(folder : URL, name : String) throws {
        let url = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            self.url = url
        }else{
            throw FlightLogFileError.fileDoesNotExist
        }
    }
    
    
    func parse(progress : ProcessingProgressReport? = nil) {
        if data == nil {
            self.data = FlightData(url: self.url, progress: progress)
            if let data = self.data {
                do {
                    self.flightSummary = try FlightSummary(data: data)
                    self.legs = self.route()
                }catch{
                    Logger.app.error("Failed to parse log file \(self.url.lastPathComponent)")
                }
            }
        }
    }
    
    func clear() {
        self.data = nil
    }
}

//MARK: - interpretation
extension FlightLogFile {
    
    func meta(key : MetaField) -> String? {
        self.parse()
        return self.data?.meta[key]
    }
    
    func updateFlightLogFileInfo(info : FlightLogFileInfo){
        try? info.updateFromFlightLog(flightLog: self)
    }
    
    private func route() -> [ FlightLeg ] {
        var rv : [FlightLeg] = []
        
        // first identify list of way points
        if let data = self.data {
            let identifiers : DatesValuesByField<String,Field> = data.datesStrings(for: [.AtvWpt])

            do {
                let stats : DatesValuesByField<ValueStats,Field> = try data.extract(dates: identifiers.dates)
                
                var previousIdentifier : String? = nil
                var previousDate : Date? = self.data?.dates.first
                
                for (idx,date) in identifiers.dates.enumerated() {
                    if let identifier = identifiers.value(for: .AtvWpt, at: idx),
                       let waypoint = Waypoint(name: identifier),
                       let startTime = previousDate {
                    
                        var validData : [Field:ValueStats] = [:]
                        for (field,val) in stats.fieldValue(at: idx) {
                            if val.isValid {
                                validData[field] = val
                            }
                        }
                        
                        
                        let leg = FlightLeg(waypoint_to: waypoint, waypoint_from: Waypoint(name: previousIdentifier),
                                            timeRange: TimeRange(start: startTime, end: date),
                                            data: validData)
                        rv.append(leg)
                        previousIdentifier = identifier
                        previousDate = date
                    }
                }
            }catch{
                Logger.app.error("Failed to extract route \(error.localizedDescription)")
            }
            
            //let first = datesDouble.valueStats(from: identifiers.dates[0], to: identifiers.dates[1])
            //print( first )
            
            
            
        }

        
        return rv
    }
}
