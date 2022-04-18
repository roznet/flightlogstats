//
//  FlightLog.swift
//  connectflight (iOS)
//
//  Created by Brice Rosenzweig on 27/06/2021.
//

import Foundation

class FlightLog {
    let url : URL
    
    var data : FlightData? = nil
    
    init(url : URL) throws {
        self.url = url
    }
    
    func parse() {
        guard let str = try? String(contentsOf: self.url, encoding: .utf8) else { return }
        let lines = str.split(whereSeparator: \.isNewline)

        if self.data == nil {
            self.data = FlightData()
        }
        self.data?.parseLines(lines: lines)
        
    }
}
