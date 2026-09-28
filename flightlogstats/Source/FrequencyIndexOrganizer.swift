//
//  FrequencyIndexOrganizer.swift
//  FlightLogStats
//
//  Persistent index behind Frequency Bingo: debounced COM1 segments and a
//  point every `step` seconds for each log, kept in its own sqlite database.
//
//  Follows the AggregatedDataOrganizer pattern (FMDB, versioned config table,
//  delete by log file name) with one deliberate difference: a version or
//  constants mismatch drops and rebuilds the index rather than disabling it,
//  so a tuning change can never leave a stale index with no signal.
//
//  Design: designs/future/frequency-bingo.md
//

import Foundation
import OSLog
import RZUtils
import RZUtilsSwift
import FMDB

extension Notification.Name {
    static let frequencyIndexChanged : Notification.Name = Notification.Name("Notification.Name.frequencyIndexChanged")
}

class FrequencyIndexOrganizer {
    private let db : FMDatabase
    private let lock = NSLock()
    let constants : FrequencyScan.Constants

    /// bump when the scan or segment logic changes: the index is then rebuilt
    static let currentDatabaseVersion = 1

    private static let configTable = "freq_config"
    private static let logsTable = "freq_logs"
    private static let segmentsTable = "freq_segments"
    private static let pointsTable = "freq_points"

    /// every log already processed, including those that yielded nothing, so they are not retried
    private var indexedLogs : Set<String> = []

    private var cachedModel : FrequencyModel? = nil
    private var cachedSince : Date? = nil

    convenience init?(databaseName : String = "frequencyIndex.db", constants : FrequencyScan.Constants = .standard) {
        let path = RZFileOrganizer.writeableFilePath(databaseName)
        let db = FMDatabase(path: path)
        guard db.open() else {
            Logger.app.error("Failed to open frequency index \(databaseName)")
            return nil
        }
        self.init(db: db, constants: constants)
    }

    init?(db : FMDatabase, constants : FrequencyScan.Constants = .standard) {
        self.db = db
        self.constants = constants
        guard self.checkOrInitDb() else { return nil }
        self.indexedLogs = self.loadIndexedLogs()
        Logger.app.info("Frequency index has \(self.indexedLogs.count) logs")
    }

    //MARK: - database setup

    /// Create the tables, or drop and recreate them if the version or constants changed
    private func checkOrInitDb() -> Bool {
        var compatible = false
        if db.tableExists(Self.configTable),
           let rs = db.executeQuery("SELECT version, step, min_dwell, min_gs FROM \(Self.configTable) ORDER BY version DESC LIMIT 1", withArgumentsIn: []) {
            if rs.next() {
                let version = Int(rs.int(forColumn: "version"))
                let step = Int(rs.int(forColumn: "step"))
                let minDwell = rs.double(forColumn: "min_dwell")
                let minGs = rs.double(forColumn: "min_gs")
                compatible = version == Self.currentDatabaseVersion
                    && step == self.constants.step
                    && minDwell.isAlmostEqual(to: self.constants.minDwell)
                    && minGs.isAlmostEqual(to: self.constants.minGroundSpeed)
                if !compatible {
                    Logger.app.info("Frequency index is version \(version) step \(step), rebuilding")
                }
            }
            rs.close()
        }
        if compatible {
            return true
        }
        return self.createTables()
    }

    private func createTables() -> Bool {
        let statements = [
            "DROP TABLE IF EXISTS \(Self.configTable)",
            "DROP TABLE IF EXISTS \(Self.logsTable)",
            "DROP TABLE IF EXISTS \(Self.segmentsTable)",
            "DROP TABLE IF EXISTS \(Self.pointsTable)",
            "CREATE TABLE \(Self.configTable) (version INTEGER, step INTEGER, min_dwell REAL, min_gs REAL)",
            "CREATE TABLE \(Self.logsTable) (log_file_name TEXT PRIMARY KEY, log_date REAL, segments INTEGER, points INTEGER)",
            "CREATE TABLE \(Self.segmentsTable) (log_file_name TEXT, seq INTEGER, freq TEXT, t_start REAL, dur_s REAL, nm REAL, lat_in REAL, lon_in REAL, alt_in REAL, trk_in REAL, lat_out REAL, lon_out REAL, alt_out REAL, prev_freq TEXT, next_freq TEXT, wpt_in TEXT)",
            "CREATE INDEX \(Self.segmentsTable)_log ON \(Self.segmentsTable) (log_file_name)",
            "CREATE TABLE \(Self.pointsTable) (log_file_name TEXT, seq INTEGER, lat REAL, lon REAL, alt REAL, trk REAL, gs REAL, freq TEXT, next_freq TEXT, nm_to_next REAL)",
            "CREATE INDEX \(Self.pointsTable)_log ON \(Self.pointsTable) (log_file_name)",
        ]
        for sql in statements {
            if !db.executeUpdate(sql, withArgumentsIn: []) {
                Logger.app.error("Failed frequency index setup \(sql): \(self.db.lastError().localizedDescription)")
                return false
            }
        }
        if !db.executeUpdate("INSERT INTO \(Self.configTable) (version, step, min_dwell, min_gs) VALUES (?,?,?,?)",
                             withArgumentsIn: [Self.currentDatabaseVersion, self.constants.step,
                                               self.constants.minDwell, self.constants.minGroundSpeed]) {
            Logger.app.error("Failed to insert frequency index config: \(self.db.lastError().localizedDescription)")
            return false
        }
        return true
    }

    private func loadIndexedLogs() -> Set<String> {
        var rv : Set<String> = []
        if let rs = db.executeQuery("SELECT log_file_name FROM \(Self.logsTable)", withArgumentsIn: []) {
            while rs.next() {
                if let name = rs.string(forColumn: "log_file_name") {
                    rv.insert(name)
                }
            }
            rs.close()
        }
        return rv
    }

    //MARK: - status

    var indexedCount : Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.indexedLogs.count
    }

    func isIndexed(logFileName : String) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.indexedLogs.contains(logFileName)
    }

    //MARK: - update

    func insertOrReplace(record : FlightLogFileRecord) {
        guard let flightLog = record.flightLog else { return }
        self.insertOrReplace(flightLog: flightLog)
    }

    /// Index a parsed log. A log with no usable COM1 data is still recorded, as empty,
    /// so the backfill does not keep coming back to it.
    func insertOrReplace(flightLog : FlightLogFile) {
        let name = flightLog.name
        let index : FrequencyLogIndex
        if let rows = flightLog.frequencyScanRows() {
            index = FrequencyScan.index(logFileName: name, rows: rows, constants: self.constants)
        }else{
            index = FrequencyLogIndex(logFileName: name, logDate: nil, segments: [], points: [])
        }
        self.insertOrReplace(index: index)
    }

    func insertOrReplace(index : FrequencyLogIndex) {
        self.lock.lock()
        defer { self.lock.unlock() }

        let name = index.logFileName
        db.beginTransaction()
        var ok = self.deleteRows(logFileName: name)

        ok = ok && db.executeUpdate("INSERT OR REPLACE INTO \(Self.logsTable) (log_file_name, log_date, segments, points) VALUES (?,?,?,?)",
                                    withArgumentsIn: [name, Self.value(index.logDate?.timeIntervalSinceReferenceDate),
                                                      index.segments.count, index.points.count])
        for (seq, s) in index.segments.enumerated() {
            guard ok else { break }
            ok = db.executeUpdate("INSERT INTO \(Self.segmentsTable) (log_file_name, seq, freq, t_start, dur_s, nm, lat_in, lon_in, alt_in, trk_in, lat_out, lon_out, alt_out, prev_freq, next_freq, wpt_in) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                                  withArgumentsIn: [name, seq, s.freq,
                                                    Self.value(s.start?.timeIntervalSinceReferenceDate),
                                                    s.duration, s.nm,
                                                    s.latIn, s.lonIn, s.altIn, s.trkIn,
                                                    s.latOut, s.lonOut, s.altOut,
                                                    Self.value(s.prevFreq), Self.value(s.nextFreq), s.waypointIn])
        }
        for (seq, p) in index.points.enumerated() {
            guard ok else { break }
            ok = db.executeUpdate("INSERT INTO \(Self.pointsTable) (log_file_name, seq, lat, lon, alt, trk, gs, freq, next_freq, nm_to_next) VALUES (?,?,?,?,?,?,?,?,?,?)",
                                  withArgumentsIn: [name, seq, p.lat, p.lon, p.alt, p.trk, p.gs, p.freq,
                                                    Self.value(p.nextFreq), Self.value(p.nmToNext)])
        }
        if ok {
            db.commit()
            self.indexedLogs.insert(name)
            self.invalidate()
        }else{
            Logger.app.error("Failed to index frequencies for \(name): \(self.db.lastError().localizedDescription)")
            db.rollback()
        }
    }

    func delete(logFileName : String) {
        self.lock.lock()
        defer { self.lock.unlock() }

        db.beginTransaction()
        let ok = self.deleteRows(logFileName: logFileName)
            && db.executeUpdate("DELETE FROM \(Self.logsTable) WHERE log_file_name = ?", withArgumentsIn: [logFileName])
        if ok {
            db.commit()
            self.indexedLogs.remove(logFileName)
            self.invalidate()
        }else{
            db.rollback()
        }
    }

    /// Empty the index, it will be rebuilt as logs are processed
    func reset() {
        self.lock.lock()
        defer { self.lock.unlock() }

        _ = self.createTables()
        self.indexedLogs = []
        self.invalidate()
    }

    /// caller holds the lock
    private func deleteRows(logFileName : String) -> Bool {
        return db.executeUpdate("DELETE FROM \(Self.segmentsTable) WHERE log_file_name = ?", withArgumentsIn: [logFileName])
            && db.executeUpdate("DELETE FROM \(Self.pointsTable) WHERE log_file_name = ?", withArgumentsIn: [logFileName])
    }

    /// caller holds the lock, so the notification is posted later: an observer
    /// asking for the model straight away would otherwise deadlock
    private func invalidate() {
        self.cachedModel = nil
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .frequencyIndexChanged, object: self)
        }
    }

    private static func value(_ v : Any?) -> Any {
        guard let v = v else { return NSNull() }
        if let d = v as? Double, !d.isFinite {
            return NSNull()
        }
        return v
    }

    //MARK: - load

    /// Everything in the index, ordered by log file name
    func logs() -> [FrequencyLogIndex] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.loadLogs()
    }

    /// The model over the whole index, cached until the index changes.
    /// - Parameter since: only use flights on or after this date
    func model(since : Date? = nil) -> FrequencyModel {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let model = self.cachedModel, self.cachedSince == since {
            return model
        }
        let mem = RZPerformance.start()
        let model = FrequencyModel(logs: self.loadLogs(), since: since)
        if let mem = mem {
            Logger.app.info("Loaded frequency model \(model.count) points, \(model.freqs.count) frequencies in \(mem)")
        }
        self.cachedModel = model
        self.cachedSince = since
        return model
    }

    /// caller holds the lock
    private func loadLogs() -> [FrequencyLogIndex] {
        var dates : [String:Date] = [:]
        var names : [String] = []
        if let rs = db.executeQuery("SELECT log_file_name, log_date FROM \(Self.logsTable) WHERE segments > 0 ORDER BY log_file_name", withArgumentsIn: []) {
            while rs.next() {
                guard let name = rs.string(forColumn: "log_file_name") else { continue }
                names.append(name)
                if !rs.columnIsNull("log_date") {
                    dates[name] = Date(timeIntervalSinceReferenceDate: rs.double(forColumn: "log_date"))
                }
            }
            rs.close()
        }

        var segments : [String:[FrequencySegment]] = [:]
        if let rs = db.executeQuery("SELECT * FROM \(Self.segmentsTable) ORDER BY log_file_name, seq", withArgumentsIn: []) {
            while rs.next() {
                guard let name = rs.string(forColumn: "log_file_name"), let segment = Self.segment(rs, logDate: dates[name]) else { continue }
                segments[name, default: []].append(segment)
            }
            rs.close()
        }

        var points : [String:[FrequencyPoint]] = [:]
        if let rs = db.executeQuery("SELECT * FROM \(Self.pointsTable) ORDER BY log_file_name, seq", withArgumentsIn: []) {
            while rs.next() {
                guard let name = rs.string(forColumn: "log_file_name"), let point = Self.point(rs) else { continue }
                points[name, default: []].append(point)
            }
            rs.close()
        }

        return names.map {
            FrequencyLogIndex(logFileName: $0, logDate: dates[$0], segments: segments[$0] ?? [], points: points[$0] ?? [])
        }
    }

    //MARK: - one log

    /// The index of one log, segments and points in time order.
    /// - Returns: nil if the log has not been indexed yet. A log indexed without usable
    ///   COM1 data (taxi only, no radios) comes back with no segments and no points.
    func logIndex(logFileName : String) -> FrequencyLogIndex? {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard self.indexedLogs.contains(logFileName) else { return nil }
        return self.loadLog(logFileName: logFileName)
    }

    /// The index of one log, indexing it first if it is not yet, through the same
    /// `insertOrReplace(flightLog:)` as the incremental hook and the backfill.
    /// Parses the log if needed and leaves it parsed. Slow on a first call: not on main.
    /// - Returns: nil if the log did not parse (unreadable, empty), in which case nothing
    ///   is recorded, so a file that is missing now is not marked as having no frequencies
    func logIndex(flightLog : FlightLogFile) -> FrequencyLogIndex? {
        let name = flightLog.name
        if let rv = self.logIndex(logFileName: name) {
            return rv
        }
        flightLog.parse()
        guard flightLog.logType == .parsed else { return nil }
        self.insertOrReplace(flightLog: flightLog)
        return self.logIndex(logFileName: name)
    }

    /// caller holds the lock
    private func loadLog(logFileName name : String) -> FrequencyLogIndex {
        var logDate : Date? = nil
        if let rs = db.executeQuery("SELECT log_date FROM \(Self.logsTable) WHERE log_file_name = ?", withArgumentsIn: [name]) {
            if rs.next(), !rs.columnIsNull("log_date") {
                logDate = Date(timeIntervalSinceReferenceDate: rs.double(forColumn: "log_date"))
            }
            rs.close()
        }

        var segments : [FrequencySegment] = []
        if let rs = db.executeQuery("SELECT * FROM \(Self.segmentsTable) WHERE log_file_name = ? ORDER BY seq", withArgumentsIn: [name]) {
            while rs.next() {
                if let segment = Self.segment(rs, logDate: logDate) {
                    segments.append(segment)
                }
            }
            rs.close()
        }

        var points : [FrequencyPoint] = []
        if let rs = db.executeQuery("SELECT * FROM \(Self.pointsTable) WHERE log_file_name = ? ORDER BY seq", withArgumentsIn: [name]) {
            while rs.next() {
                if let point = Self.point(rs) {
                    points.append(point)
                }
            }
            rs.close()
        }
        return FrequencyLogIndex(logFileName: name, logDate: logDate, segments: segments, points: points)
    }

    //MARK: - rows

    private static func segment(_ rs : FMResultSet, logDate : Date?) -> FrequencySegment? {
        guard let name = rs.string(forColumn: "log_file_name"), let freq = rs.string(forColumn: "freq") else { return nil }
        let start : Date? = rs.columnIsNull("t_start") ? nil : Date(timeIntervalSinceReferenceDate: rs.double(forColumn: "t_start"))
        return FrequencySegment(freq: freq,
                                logFileName: name,
                                logDate: logDate,
                                start: start,
                                duration: rs.double(forColumn: "dur_s"),
                                nm: rs.double(forColumn: "nm"),
                                latIn: rs.double(forColumn: "lat_in"),
                                lonIn: rs.double(forColumn: "lon_in"),
                                altIn: rs.double(forColumn: "alt_in"),
                                trkIn: rs.double(forColumn: "trk_in"),
                                latOut: rs.double(forColumn: "lat_out"),
                                lonOut: rs.double(forColumn: "lon_out"),
                                altOut: rs.double(forColumn: "alt_out"),
                                prevFreq: rs.string(forColumn: "prev_freq"),
                                nextFreq: rs.string(forColumn: "next_freq"),
                                waypointIn: rs.string(forColumn: "wpt_in") ?? "")
    }

    private static func point(_ rs : FMResultSet) -> FrequencyPoint? {
        guard let freq = rs.string(forColumn: "freq") else { return nil }
        return FrequencyPoint(lat: rs.double(forColumn: "lat"),
                              lon: rs.double(forColumn: "lon"),
                              alt: rs.double(forColumn: "alt"),
                              trk: rs.double(forColumn: "trk"),
                              gs: rs.double(forColumn: "gs"),
                              freq: freq,
                              nextFreq: rs.string(forColumn: "next_freq"),
                              nmToNext: rs.columnIsNull("nm_to_next") ? nil : rs.double(forColumn: "nm_to_next"))
    }
}

//MARK: - Extracting the rows from a parsed log

extension FrequencyScan.Rows {
    /// The columns the index needs, from a parsed log. Rows without a COM1 or a
    /// position are dropped, as the reference scan does. Nil for logs without radios.
    init?(data : FlightData) {
        let doubles = data.doubleDataFrame()
        let strings = data.categoricalDataFrame()
        guard let com1 = strings.values[.COM1],
              let lat = doubles.values[.Latitude],
              let lon = doubles.values[.Longitude],
              let alt = doubles.values[.AltMSL]
        else {
            return nil
        }
        // both frames are built from the same dates and must line up row for row
        guard doubles.indexes == strings.indexes, com1.count == doubles.count else {
            Logger.app.error("Frequency scan: inconsistent rows \(doubles.count) vs \(strings.count)")
            return nil
        }
        let trk = doubles.values[.TRK]
        let gs = doubles.values[.GndSpd]
        let waypoint = strings.values[.AtvWpt]

        func orZero(_ v : Double?) -> Double {
            guard let v = v, v.isFinite else { return 0.0 }
            return v
        }

        self.init()
        self.logDate = doubles.indexes.first
        for i in 0..<doubles.count {
            let freq = com1[i].trimmingCharacters(in: .whitespaces)
            guard !freq.isEmpty, lat[i].isFinite, lon[i].isFinite else { continue }
            self.append(time: doubles.indexes[i], com1: freq, lat: lat[i], lon: lon[i],
                        alt: orZero(alt[i]), trk: orZero(trk?[i]), gs: orZero(gs?[i]),
                        waypoint: waypoint?[i].trimmingCharacters(in: .whitespaces) ?? "")
        }
    }
}
