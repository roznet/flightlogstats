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
    
    
    func parse() {
        if data == nil {
            self.data = FlightData(url: self.url)
            if let data = self.data {
                do {
                    self.flightSummary = try FlightSummary(data: data)
                }catch{
                    Logger.app.error("Failed to parse log file")
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
    
    func meta(key : MetaKey) -> String? {
        self.parse()
        return self.data?.meta[key.rawValue]
    }
    
    func updateFlightLogFileInfo(info : FlightLogFileInfo){
        try? info.updateFromFlightLog(flightLog: self)
    }
    
    func route(fields : [ FlightLogFile.Field ]) -> [ FlightLeg ] {
        var rv : [FlightLeg] = []
        
        // first identify list of way points
        self.parse()
        if let data = self.data {
            let identifiers = data.datesStrings(for: ["AtvWpt"])
            print(identifiers)
            let datesDouble = data.datesDoubles(for: FlightLogFile.fields(fields))
            
            //let first = datesDouble.valueStats(from: identifiers.dates[0], to: identifiers.dates[1])
            //print( first )
            
            
            
        }

        
        return rv
    }
}
