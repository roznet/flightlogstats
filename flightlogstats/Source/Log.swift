//
//  Log.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 24/04/2022.
//

import Foundation
import OSLog

extension OSLogEntryLog {
    var levelDescription : String {
        switch self.level {
        case .undefined:
            return "UNDF"
        case .error:
            return "ERR "
        case .debug:
            return "DBG "
        case .notice:
            return "WARN"
        case .info:
            return "INFO"
        case .fault:
            return "FAUL"
        @unknown default:
            return "UNKN"
        }
    }
}

extension String.StringInterpolation {
    mutating func appendInterpolation(_ value : OSLogEntryLog) {
        //appendLiteral(value.date.formatted(date: .abbreviated, time: .standard))
        appendLiteral("\(value.date) \(value.processIdentifier):\(value.threadIdentifier)  [\(value.category)] \(value.levelDescription) \(value.composedMessage)")
    }
}

public struct MyLogger {
    let logger : Logger
    init(subsystem: String, category: String){
        self.logger = Logger(subsystem: subsystem, category: category)
    }
    
    func info(_ message : String, function : String = #function) {
        self.logger.info("\(function) \(message)")
    }
    func error(_ message : String, function : String = #function) {
        self.logger.error("\(function) \(message)")
    }
    func warning(_ message : String, function : String = #function) {
        self.logger.notice("\(function) \(message)")
    }
}

extension Logger {
    public static let app = MyLogger(subsystem: Bundle.main.bundleIdentifier!, category: "app")
    public static let ui = MyLogger(subsystem: Bundle.main.bundleIdentifier!, category: "ui")
    public static let sync = MyLogger(subsystem: Bundle.main.bundleIdentifier!, category: "sync")
    public static let net = MyLogger(subsystem: Bundle.main.bundleIdentifier!, category: "net")
    
    static func logEntriesFormatted() -> [String] {
        var rv : [String] = []
        do {
            let l = try Self.logEntries()
            for one in l {
                rv.append("\(one)")
            }
        }catch{
            rv.append(error.localizedDescription)
        }
        return rv
    }
    
    static func logEntries() throws -> [OSLogEntryLog]{
        let logStore = try OSLogStore(scope: .currentProcessIdentifier)
        
        let oneHour = logStore.position(date: Date().addingTimeInterval(-3600))
        
        let entries = try logStore.getEntries(at: oneHour)
        
        return entries.compactMap { $0 as? OSLogEntryLog }.filter { $0.subsystem == Bundle.main.bundleIdentifier! }
    }

}
