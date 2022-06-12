//
//  ProgressReport.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 28/05/2022.
//

import Foundation

extension Notification.Name {
    static let kProgressUpdate = Notification.Name("kProgressUpdate")
}

@objc class ProgressReport : NSObject {
    enum State : Comparable {
        case complete
        case progressing(Double)
        case error(String)
    }
    
    /**
     * state and message
     */
    typealias Callback = (_ : ProgressReport) -> Void
    
    private(set) var message : String
    private(set) var state : State
    
    private var lastDate : Date
    private let callback : Callback
    
    init(message : String, callback : @escaping Callback = { _ in }){
        self.message = message
        self.lastDate = Date()
        self.callback = callback
        self.state = .complete
    }
    
    func update(state : State, message : String? = nil) {
        // if already reported, return
        guard state != self.state else { return }
        
        // if progressing only update after 0.1seconds
        let now = Date()
        switch state {
        case .progressing(let pct):
            // if not at 0 (start) or end (1.0) only report once every few 100ms
            if pct > 0.0 && pct < 1.0 && now.timeIntervalSince(self.lastDate) < 0.2 {
                return
            }
            fallthrough
        default:
            if let message = message {
                self.message = message
            }
            self.state = state
            self.lastDate = now
            self.callback(self)
            NotificationCenter.default.post(name: .kProgressUpdate, object: self)
        }
    }
}

extension ProgressReport.State : CustomStringConvertible {
    var description: String {
        switch self {
        case .complete:
            return "State<.complete>"
        case .error(let error):
            return "State<.error(\(error)>"
        case .progressing(let pct):
            return "State<.progressing(\(pct))>"
        }
    }
}
