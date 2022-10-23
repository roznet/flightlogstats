//
//  AvionicsSystem.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 23/10/2022.
//

import Foundation
import OSLog

class AvionicsSystem : CustomStringConvertible {
    
    let info : [String:String]
    let aircraftIdentifier : String
    let airframeName : String
    let systemId : String
    
    var description: String { return "Avionics(\(systemId),\(aircraftIdentifier),\(airframeName))" }
    
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
        let systemInfo = lines[0]
        //var info : [String:String] = [:]
        
        let keys = lines[1].split(separator: ",").map { $0.trimmingCharacters(in: trimCharSet)}
        let values = lines[2].split(separator: ",").map { $0.trimmingCharacters(in: trimCharSet)}
        guard keys.count == values.count else { return nil }
        self.info = Dictionary(uniqueKeysWithValues: zip(keys,values))
        
        guard let identifier = self.info["Aircraft Identifier"],
              let airframe = self.info["Airframe Name"],
              let system = self.info["System ID"] else { return nil }
        
        self.airframeName = airframe
        self.systemId = system.replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
        self.aircraftIdentifier = identifier
    }
    
    
}
