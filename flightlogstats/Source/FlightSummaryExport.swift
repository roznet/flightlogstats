//
//  FlightSummaryExport.swift
//  FlightLogStats
//
//  One flight's summary as JSON, for other tools (logbook, expenses, an assistant):
//  saved to Dropbox and shared from the log list's Share Summary.
//

import Foundation
import OSLog
import RZFlight
import UIKit

/// What a logbook or an expense sheet needs from a flight, from a full parse: times in
/// UTC, durations, fuel in litres and US gallons, distance, airports.
struct FlightSummaryExport : Codable, Equatable {
    static let formatName = "flightlogstats.flight-summary"
    /// change when a field changes meaning or goes away; adding one keeps the version
    static let formatVersion = 1

    struct Aircraft : Codable, Equatable {
        var registration : String?
        var airframe : String?
        var systemId : String?
    }

    struct Airport : Codable, Equatable {
        var icao : String
        var name : String?
    }

    /// Every time in UTC. Engine: first/last row with engine power; block: first/last
    /// ground movement; takeoff/landing: IAS above 35 kt. The log starts when the
    /// avionics are powered, so an engine started before them shows at the log start.
    struct Times : Codable, Equatable {
        var logStart : Date?
        var engineOn : Date?
        var blockOff : Date?
        var takeoff : Date?
        var landing : Date?
        var blockOn : Date?
        var engineOff : Date?
        var logEnd : Date?
    }

    struct Durations : Codable, Equatable {
        var engineMinutes : Int?
        var blockMinutes : Int?
        var airborneMinutes : Int?
        /// decimal hours, two decimals
        var engineHours : Double?
        var blockHours : Double?
        var airborneHours : Double?
    }

    /// Tank quantities at the start and end, used from the tanks and from the fuel flow
    /// (the totaliser), in one unit.
    struct Fuel : Codable, Equatable {
        var unit : String
        var startLeft : Double
        var startRight : Double
        var startTotal : Double
        var endLeft : Double
        var endRight : Double
        var endTotal : Double
        var usedTanks : Double
        var usedTotalizer : Double
    }

    var format : String = Self.formatName
    var version : Int = Self.formatVersion
    var logFile : String
    /// one line for a person: date, aircraft, route, block and airborne times, fuel
    var summary : String
    /// UTC day of the block off (or log start)
    var date : String?
    var aircraft : Aircraft
    var departure : Airport?
    var arrival : Airport?
    var route : [String]
    var timesUtc : Times
    var durations : Durations
    var distanceNm : Double
    var maxAltitudeFt : Double
    var fuelLiters : Fuel
    var fuelUsGallons : Fuel

    init(logFile : String, summary flight : FlightSummary, aircraft : Aircraft,
         departureIcao : String? = nil, arrivalIcao : String? = nil) {
        self.logFile = logFile
        self.aircraft = aircraft

        if let airport = flight.startAirport {
            self.departure = Airport(icao: airport.icao, name: airport.name)
        }else if let icao = departureIcao {
            self.departure = Airport(icao: icao, name: nil)
        }
        if let airport = flight.endAirport {
            self.arrival = Airport(icao: airport.icao, name: airport.name)
        }else if let icao = arrivalIcao {
            self.arrival = Airport(icao: icao, name: nil)
        }
        self.route = flight.route.map { $0.name }

        self.timesUtc = Times(logStart: flight.hobbs?.start,
                              engineOn: flight.engineOn?.start,
                              blockOff: flight.moving?.start,
                              takeoff: flight.flying?.start,
                              landing: flight.flying?.end,
                              blockOn: flight.moving?.end,
                              engineOff: flight.engineOn?.end,
                              logEnd: flight.hobbs?.end)
        self.durations = Durations(engineMinutes: Self.minutes(flight.engineOn),
                                   blockMinutes: Self.minutes(flight.moving),
                                   airborneMinutes: Self.minutes(flight.flying),
                                   engineHours: Self.hours(flight.engineOn),
                                   blockHours: Self.hours(flight.moving),
                                   airborneHours: Self.hours(flight.flying))
        self.distanceNm = Self.rounded(flight.distanceInNm, places: 1)
        self.maxAltitudeFt = flight.altitudeInFeet.rounded()
        self.fuelLiters = Self.fuel(flight, unit: .liters, name: "l")
        self.fuelUsGallons = Self.fuel(flight, unit: .gallons, name: "usgal")

        if let day = flight.moving?.start ?? flight.hobbs?.start {
            self.date = Self.dayFormatter.string(from: day)
        }
        self.summary = ""
        self.summary = self.headline
    }

    //MARK: - Building

    /// The summary of a log from a full parse: the quick parse samples every 5 minutes,
    /// too coarse for logbook times. Uses the record's parsed log when it has one,
    /// otherwise parses the file without keeping it. Call on `AppDelegate.worker`.
    /// - Returns: nil if the file is not on this device or has no flight data
    static func make(record : FlightLogFileRecord, folder : URL) -> FlightSummaryExport? {
        guard let name = record.log_file_name else { return nil }
        var flight : FlightSummary? = nil
        if let log = record.flightLog, case .parsed = log.logType {
            flight = log.flightSummary
        }
        if flight == nil {
            let url = folder.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path), let log = FlightLogFile(url: url) else {
                return nil
            }
            log.parse()
            if case .parsed = log.logType {
                flight = log.flightSummary
            }
        }
        guard let flight = flight else {
            Logger.app.error("No summary for \(name)")
            return nil
        }
        let registration = record.aircraftRecord?.aircraftIdentifier
        let aircraft = Aircraft(registration: (registration?.isEmpty ?? true) ? nil : registration,
                                airframe: record.airframe_name,
                                systemId: record.system_id)
        return FlightSummaryExport(logFile: name, summary: flight, aircraft: aircraft,
                                   departureIcao: record.start_airport_icao, arrivalIcao: record.end_airport_icao)
    }

    //MARK: - Output

    static let encoder : JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder : JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func json() throws -> Data {
        return try Self.encoder.encode(self)
    }

    /// Copied from the share sheet: the headline, then the JSON.
    func clipboardText() -> String {
        guard let data = try? self.json(), let json = String(data: data, encoding: .utf8) else {
            return self.summary
        }
        return "\(self.summary)\n\n\(json)\n"
    }

    /// `2026-10-26_EGTF-LFAT_log_261026_093012_EGTF.json`: sorts by date, readable in a
    /// folder listing, unique by the log name.
    var fileName : String {
        let base = (self.logFile as NSString).deletingPathExtension
        var parts : [String] = []
        if let date = self.date {
            parts.append(date)
        }
        let route = [self.departure?.icao, self.arrival?.icao].compactMap { $0 }.joined(separator: "-")
        if !route.isEmpty {
            parts.append(route)
        }
        parts.append(base)
        return parts.joined(separator: "_") + ".json"
    }

    private var headline : String {
        var parts : [String] = []
        if let date = self.date {
            parts.append(date)
        }
        if let registration = self.aircraft.registration {
            parts.append(registration)
        }
        let route = [self.departure?.icao, self.arrival?.icao].compactMap { $0 }.joined(separator: "-")
        if !route.isEmpty {
            parts.append(route)
        }
        if let off = self.timesUtc.blockOff, let on = self.timesUtc.blockOn, let hours = self.durations.blockHours {
            parts.append("block \(Self.hhmm(off))-\(Self.hhmm(on))Z (\(hours) h)")
        }
        if let takeoff = self.timesUtc.takeoff, let landing = self.timesUtc.landing, let hours = self.durations.airborneHours {
            parts.append("airborne \(Self.hhmm(takeoff))-\(Self.hhmm(landing))Z (\(hours) h)")
        }
        parts.append("fuel used \(self.fuelLiters.usedTotalizer) l / \(self.fuelUsGallons.usedTotalizer) usgal")
        if self.distanceNm > 0 {
            parts.append("\(self.distanceNm) nm")
        }
        return parts.joined(separator: ", ")
    }

    //MARK: - Helpers

    private static let dayFormatter : DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timeFormatter : DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func hhmm(_ date : Date) -> String {
        return self.timeFormatter.string(from: date)
    }

    private static func minutes(_ range : TimeRange?) -> Int? {
        guard let range = range else { return nil }
        return Int((range.elapsed / 60.0).rounded())
    }

    private static func hours(_ range : TimeRange?) -> Double? {
        guard let range = range else { return nil }
        return self.rounded(range.elapsed / 3600.0, places: 2)
    }

    private static func rounded(_ value : Double, places : Int) -> Double {
        let scale = pow(10.0, Double(places))
        return (value * scale).rounded() / scale
    }

    private static func fuel(_ flight : FlightSummary, unit : UnitVolume, name : String) -> Fuel {
        let start = flight.fuelStart.converted(to: unit)
        let end = flight.fuelEnd.converted(to: unit)
        let used = flight.fuelUsed.converted(to: unit)
        let totalizer = flight.fuelTotalizer.converted(to: unit)
        return Fuel(unit: name,
                    startLeft: self.rounded(start.left, places: 1),
                    startRight: self.rounded(start.right, places: 1),
                    startTotal: self.rounded(start.total, places: 1),
                    endLeft: self.rounded(end.left, places: 1),
                    endRight: self.rounded(end.right, places: 1),
                    endTotal: self.rounded(end.total, places: 1),
                    usedTanks: self.rounded(used.total, places: 1),
                    usedTotalizer: self.rounded(totalizer.total, places: 1))
    }
}

//MARK: - Share sheet

/// The share sheet items of a summary: the JSON file for Save to Files, Mail, AirDrop;
/// the headline and JSON as text for Copy; the headline as the body of a message.
enum FlightSummaryShare {
    /// The summary written to a temporary file named like its Dropbox copy.
    /// - Returns: the items for `UIActivityViewController`, and the file to remove after
    static func items(for export : FlightSummaryExport) throws -> (items : [Any], file : URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("summary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(export.fileName)
        try export.json().write(to: file, options: .atomic)
        return ([FileItem(file: file), TextItem(export: export)], folder)
    }

    /// The file, except for Copy, which takes the text instead.
    final class FileItem : NSObject, UIActivityItemSource {
        let file : URL
        init(file : URL) { self.file = file }

        func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
            return self.file
        }

        func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
            return activityType == .copyToPasteboard ? nil : self.file
        }
    }

    /// Text where text helps: the headline and JSON for Copy, the headline for a mail or
    /// message body; nothing elsewhere, so Save to Files saves only the JSON.
    final class TextItem : NSObject, UIActivityItemSource {
        let export : FlightSummaryExport
        init(export : FlightSummaryExport) { self.export = export }

        func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
            return self.export.summary
        }

        func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
            if activityType == .copyToPasteboard {
                return self.export.clipboardText()
            }
            if activityType == .mail || activityType == .message {
                return self.export.summary
            }
            return nil
        }

        func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
            return "Flight summary \(self.export.summary)"
        }
    }
}
