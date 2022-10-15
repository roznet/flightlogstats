//
//  Log.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 24/04/2022.
//

import Foundation
import OSLog

extension Logger {
    public static let app = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "app")
    public static let ui = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ui")
    public static let sync = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "sync")
    public static let net = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "net")
}
