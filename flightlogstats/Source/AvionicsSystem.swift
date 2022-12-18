//
//  AvionicsSystem.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 23/10/2022.
//

import Foundation
import OSLog
import CoreData

class AvionicsSystem : CustomStringConvertible, Equatable, Codable {
    typealias SystemId = String
    typealias AircraftIdentifier = String
    
    let info : [String:String]
    let aircraftIdentifier : AircraftIdentifier
    let airframeName : String
    let systemId : SystemId
    
    var description: String { return "Avionics(\(systemId),\(aircraftIdentifier),\(airframeName))" }
    
    var uniqueFileName : String { return "sys_\(systemId).json" }
    
    static func ==(lhs: AvionicsSystem, rhs: AvionicsSystem) -> Bool {
        return lhs.systemId == rhs.systemId && lhs.airframeName == rhs.airframeName && lhs.aircraftIdentifier == rhs.aircraftIdentifier
    }
    
    init(aircraftIdentifier : AircraftIdentifier, airframeName : String, systemId : SystemId) {
        self.airframeName = airframeName
        self.aircraftIdentifier = aircraftIdentifier
        self.systemId = systemId
        self.info = [:]
    }
    
    static private func parse(url : URL) -> [String:String] {
        var lines : [String.SubSequence] = []
        do {
            let str = try String(contentsOf: url, encoding: .macOSRoman)
            lines = str.split(whereSeparator: \.isNewline)
        }catch {
            Logger.app.error("Failed to read \(url.lastPathComponent) \(error.localizedDescription)")
            return [:]
        }
        
        let trimCharSet = CharacterSet(charactersIn: "\" ")
        guard lines.count > 3 else { return [:] }
        
        let keys = lines[1].split(separator: ",").map { $0.trimmingCharacters(in: trimCharSet)}
        let values = lines[2].split(separator: ",").map { $0.trimmingCharacters(in: trimCharSet)}
        guard keys.count == values.count else { return [:] }
        return Dictionary(uniqueKeysWithValues: zip(keys,values))
    }
    
    static func from(jsonUrl : URL) -> AvionicsSystem? {
        do {
            let data = try Data(contentsOf: jsonUrl)
            return try JSONDecoder().decode(AvionicsSystem.self, from: data)
        }catch{
            Logger.app.error("Failed to parse aircraft \(jsonUrl.lastPathComponent)")
            return nil
        }
            
    }
    
    init?(url : URL) {
        self.info = Self.parse(url: url)
        // we need a system id,
        guard let system = self.info["System ID"] else { return nil }
        self.systemId = system.replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
        
        //but for rest not necessary
        if let identifier = self.info["Aircraft Identifier"] {
            self.aircraftIdentifier = identifier
        }else{
            self.aircraftIdentifier = ""
        }
        
        if let airframe = self.info["Airframe Name"] {
            self.airframeName = airframe
        }else{
            self.airframeName = ""
        }
    }
    

}
