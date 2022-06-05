//
//  ProgressReport.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 28/05/2022.
//

import Foundation

struct ProgressReport {
    enum State {
        case complete
        case progressing(Double)
        case error(Error)
    }
    
    typealias Callback = (_ : State) -> Void
}
