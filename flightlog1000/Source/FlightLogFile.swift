//
//  FlightLog.swift
//  connectflight (iOS)
//
//  Created by Brice Rosenzweig on 27/06/2021.
//

import Foundation

class FlightLogFile {
    enum FlightLogFileError : Error {
        case fileDoesNotExist
    }
    
    let url : URL 
    var name : String { return url.lastPathComponent }
    
    var description : String { return "<FlightLog:\(name)>" }
    
    var data : FlightData? = nil
    var isParsed : Bool { return data != nil }
    
    
    init(url : URL) {
        self.url = url
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
            guard let str = try? String(contentsOf: self.url, encoding: .utf8) else { return }
            let lines = str.split(whereSeparator: \.isNewline)
            
            if self.data == nil {
                self.data = FlightData()
            }
            self.data?.parseLines(lines: lines)
        }
    }
}

//MARK: - interpretation
extension FlightLogFile {
    
    func updateFlightLogFileInfo(info : FlightLogFileInfo){
        info.flightLog = self
        info.log_file_name = self.name
        
        
        if let data = self.data {
            let values = data.datesDoubles(for: FlightLogFile.fields([.GndSpd,.IAS,.E1_PctPwr,.FQtyL,.FQtyR]) )

            if let system_id = data.meta["system_id"] {
                info.system_id = system_id
            }
            
            if let airframe_name = data.meta["airframe_name"] {
                info.airframe_name = airframe_name
            }

            let engineOn = values.dropFirst(field: FlightLogFile.field(.E1_PctPwr)) { $0 > 0.0 }?.dropLast(field: FlightLogFile.field(.E1_PctPwr)) { $0 > 0.0 }
            
            let moving = engineOn?.dropFirst(field: FlightLogFile.field(.GndSpd)) { $0 > 0.0 }?.dropLast(field: FlightLogFile.field(.GndSpd)) { $0 > 0.0 }
            let flying = engineOn?.dropFirst(field: FlightLogFile.field(.IAS)) { $0 > 35.0 }?.dropLast(field: FlightLogFile.field(.IAS)) { $0 > 35.0 }
            
            info.start_time = data.dates.first
            info.end_time = data.dates.last

            if let moving_start = moving?.first(field: FlightLogFile.field(.GndSpd))?.date {
                info.start_time_moving = moving_start
            }else{
                info.start_time_moving = info.start_time
            }
            if let moving_end = moving?.last(field: FlightLogFile.field(.GndSpd))?.date {
                info.end_time_moving = moving_end
            }else{
                info.end_time_moving = info.end_time
            }

            if let flying_start = flying?.first(field: FlightLogFile.field(.GndSpd))?.date {
                info.start_time_flying = flying_start
            }else{
                info.start_time_flying = info.start_time
            }
            if let flying_end = flying?.last(field: FlightLogFile.field(.GndSpd))?.date {
                info.end_time_flying = flying_end
            }else{
                info.end_time_flying = info.end_time
            }

            if let fuel_start_l = values.first(field: FlightLogFile.field(.FQtyL))?.value {
                info.start_fuel_quantity_left = fuel_start_l
            }
            if let fuel_start_r = values.first(field: FlightLogFile.field(.FQtyR))?.value {
                info.start_fuel_quantity_right = fuel_start_r
            }

            if let fuel_end_l = values.last(field: FlightLogFile.field(.FQtyL))?.value {
                info.end_fuel_quantity_left = fuel_end_l
            }
            if let fuel_end_r = values.last(field: FlightLogFile.field(.FQtyR))?.value {
                info.end_fuel_quantity_right = fuel_end_r
            }
        }        
    }
}
