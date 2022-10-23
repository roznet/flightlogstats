//
//  AvionicsSystem.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 23/10/2022.
//

import Foundation
import OSLog

class AvionicsSystem : CustomStringConvertible, Codable {
    
    let info : [String:String]
    let aircraftIdentifier : String
    let airframeName : String
    let systemId : String
    
    var description: String { return "Avionics(\(systemId),\(aircraftIdentifier),\(airframeName))" }
    
    var uniqueFileName : String { return "sys_\(systemId).json" }
    
    init?(url : URL) {
        var lines : [String.SubSequence] = []
        do {
            let str = try String(contentsOf: url, encoding: .macOSRoman)
            lines = str.split(whereSeparator: \.isNewline)
        }catch {
            Logger.app.error("Failed to read \(url.lastPathComponent) \(error.localizedDescription)")
            return nil
        }
        
        let trimCharSet = CharacterSet(charactersIn: "\" ")
        guard lines.count > 3 else { return nil }
        
        let keys = lines[1].split(separator: ",").map { $0.trimmingCharacters(in: trimCharSet)}
        let values = lines[2].split(separator: ",").map { $0.trimmingCharacters(in: trimCharSet)}
        guard keys.count == values.count else { return nil }
        self.info = Dictionary(uniqueKeysWithValues: zip(keys,values))

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
