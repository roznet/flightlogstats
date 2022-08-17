//
//  ProgressReport.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 28/05/2022.
//

import Foundation
import OSLog

extension Notification.Name {
    static let progressUpdate = Notification.Name("progressUpdate")
}

@objc class ProgressReport : NSObject {
    enum State : Comparable {
        case start
        case complete
        case progressing(Double)
        case error(String)
    }
    
    enum Message : String, CustomStringConvertible{
        case updatingInfo = "Updating Info"
        case iCloudSync = "Sync iCloud"
        case parsingInfo = "Parsing Info"
        case addingFiles = "Adding Files"
        
        var description: String { return self.rawValue }
    }
    
    /**
     * state and message
     */
    typealias Callback = (_ : ProgressReport) -> Void
    
    private(set) var message : Message
    private(set) var state : State
    
    private var startDate : Date
    private var lastDate : Date
    private let callback : Callback
    
    static let minimumTimeInterval : TimeInterval = 0.2
    
    var fastProcessing : Bool {
        let interval = lastDate.timeIntervalSince(startDate) < Self.minimumTimeInterval
        return interval        
    }
    
    init(message : Message, callback : @escaping Callback = { _ in }){
        self.message = message
        self.startDate = Date()
        self.lastDate = Date()
        self.callback = callback
        self.state = .start
    }
    
    func update(state : State, message : Message? = nil) {
        // if already reported, return
        guard state != self.state else { return }
        
        // if progressing only update after 0.1seconds
        let now = Date()
        if state == .start {
            self.startDate = Date()
        }
        if let message = message {
            self.message = message
        }
        switch state {
        case .progressing(let pct):
            // if not at 0 (start) or end (1.0) only report once every few 100ms
            if pct > 0.0 && pct < 1.0 && now.timeIntervalSince(self.lastDate) < Self.minimumTimeInterval {
                return
            }
            fallthrough
        default:
            self.state = state
            self.lastDate = now
            self.callback(self)
            NotificationCenter.default.post(name: .progressUpdate, object: self)
        }
    }
}

extension ProgressReport {
    override var description: String {
        return "ProgressReport(\(self.message), \(self.state))"
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
        case .start:
            return "State<.none)>"
        }
    }
}
