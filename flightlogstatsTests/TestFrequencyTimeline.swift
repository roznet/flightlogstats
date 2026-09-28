//
//  TestFrequencyTimeline.swift
//  FlightLogStatsTests
//
//  Per-flight frequency timeline: the one-log query of the frequency index and
//  the rows the Frequencies tab shows, on real logs from TestAssets.
//

import XCTest
@testable import FlightLogStats
import CoreLocation
import FMDB
import RZUtils

final class TestFrequencyTimeline: XCTestCase {

    private var db : FMDatabase? = nil
    private let dbname = "test_frequencyTimeline.db"

    override func setUpWithError() throws {
        RZFileOrganizer.removeEditableFile(self.dbname)
        let db = FMDatabase(path: RZFileOrganizer.writeableFilePath(self.dbname))
        db.open()
        self.db = db
    }

    override func tearDownWithError() throws {
        self.db?.close()
        self.db = nil
        RZFileOrganizer.removeEditableFile(self.dbname)
    }

    private func parsedLog(_ sample : TestLogFileSamples) throws -> FlightLogFile {
        let url = try XCTUnwrap(sample.url)
        let log = try XCTUnwrap(FlightLogFile(url: url))
        log.parse()
        return log
    }

    /// The one-log query returns what was indexed for that log only, in time order,
    /// and indexes a log that is not there yet through insertOrReplace(flightLog:)
    func testPerFlightQuery() throws {
        let organizer = try XCTUnwrap(FrequencyIndexOrganizer(db: try XCTUnwrap(self.db)))

        let flight3 = try self.parsedLog(.flight3)
        let diamond = try self.parsedLog(.diamond)
        organizer.insertOrReplace(flightLog: flight3)
        organizer.insertOrReplace(flightLog: diamond)

        let name = TestLogFileSamples.flight3.rawValue + ".csv"
        let one = try XCTUnwrap(organizer.logIndex(logFileName: name))
        XCTAssertEqual(one.logFileName, name)
        // same answer as the whole-corpus load, restricted to this log
        let fromAll = try XCTUnwrap(organizer.logs().first { $0.logFileName == name })
        XCTAssertEqual(one.segments.map { $0.freq }, fromAll.segments.map { $0.freq })
        XCTAssertEqual(one.points.count, fromAll.points.count)
        XCTAssertEqual(one.logDate, fromAll.logDate)
        XCTAssertTrue(one.segments.allSatisfy { $0.logFileName == name })

        // matches the scan of the log itself: count, order and durations
        let rows = try XCTUnwrap(flight3.frequencyScanRows())
        let scanned = FrequencyScan.index(logFileName: name, rows: rows)
        XCTAssertEqual(one.segments.count, 6)
        XCTAssertEqual(one.segments.map { $0.freq }, scanned.segments.map { $0.freq })
        XCTAssertEqual(one.segments.map { $0.freq }, ["119.655", "120.275", "120.180", "133.180", "134.355", "123.430"])
        XCTAssertEqual(one.points.count, scanned.points.count)
        for (a, b) in zip(one.segments, scanned.segments) {
            XCTAssertEqual(a.duration, b.duration, accuracy: 1e-6)
            XCTAssertEqual(a.waypointIn, b.waypointIn)
        }

        // time order
        let starts = one.segments.compactMap { $0.start }
        XCTAssertEqual(starts.count, one.segments.count)
        XCTAssertEqual(starts, starts.sorted())

        // not indexed: nil from the name, indexed on demand from the log
        let other = TestLogFileSamples.flight2.rawValue + ".csv"
        XCTAssertNil(organizer.logIndex(logFileName: other))
        let flight2 = try XCTUnwrap(FlightLogFile(url: try XCTUnwrap(TestLogFileSamples.flight2.url)))
        let onDemand = try XCTUnwrap(organizer.logIndex(flightLog: flight2))
        XCTAssertTrue(organizer.isIndexed(logFileName: other))
        XCTAssertEqual(onDemand.segments.count, 5)
        XCTAssertEqual(organizer.logIndex(logFileName: other)?.segments.count, 5)

        // indexed but without signal: empty, not nil
        let taxi = try self.parsedLog(.taxiOnly)
        let taxiIndex = try XCTUnwrap(organizer.logIndex(flightLog: taxi))
        XCTAssertTrue(taxiIndex.segments.isEmpty)
        XCTAssertTrue(taxiIndex.points.isEmpty)
    }

    /// Rows: one per segment, numbered in order, durations within the flight time,
    /// and every indexed point drawn on the segment it was sampled from
    func testTimelineRows() throws {
        let organizer = try XCTUnwrap(FrequencyIndexOrganizer(db: try XCTUnwrap(self.db)))
        let samples : [TestLogFileSamples] = [.flight3, .diamond, .tbm930]
        for sample in samples {
            let log = try self.parsedLog(sample)
            let index = try XCTUnwrap(organizer.logIndex(flightLog: log))
            let scanRows = try XCTUnwrap(log.frequencyScanRows())
            let label = sample.rawValue

            let rows = FrequencyTimeline.rows(index: index)
            XCTAssertEqual(rows.count, index.segments.count, label)
            XCTAssertGreaterThan(rows.count, 2, label)
            XCTAssertEqual(rows.map { $0.number }, Array(1...rows.count), label)
            XCTAssertEqual(rows.map { $0.freq }, index.segments.map { $0.freq }, label)
            XCTAssertEqual(rows.map { $0.fix }, index.segments.map { $0.waypointIn }, label)

            let elapsed = rows.compactMap { $0.elapsed }
            XCTAssertEqual(elapsed.count, rows.count, label)
            XCTAssertEqual(elapsed, elapsed.sorted(), label)
            XCTAssertGreaterThanOrEqual(elapsed.first ?? -1.0, 0.0, label)

            // durations sum to within the flight time: only the flicker dropped by the
            // debounce is missing (0.991 to 1.0 of it over the TestAssets logs in freq.py)
            let flightTime = try XCTUnwrap(scanRows.time.last).timeIntervalSince(try XCTUnwrap(scanRows.time.first))
            let total = rows.reduce(0.0) { $0 + $1.duration }
            XCTAssertLessThanOrEqual(total, flightTime, label)
            XCTAssertGreaterThan(total, 0.95 * flightTime, label)

            // every point assigned, each to a segment of its own frequency
            let grouped = FrequencyTimeline.pointsBySegment(segments: index.segments, points: index.points)
            XCTAssertEqual(grouped.reduce(0) { $0 + $1.count }, index.points.count, label)
            for (segment, points) in zip(index.segments, grouped) {
                XCTAssertTrue(points.allSatisfy { $0.freq == segment.freq && $0.nextFreq == segment.nextFreq }, label)
            }
            // and the map line runs entry, points, exit
            for (row, points) in zip(rows, grouped) {
                XCTAssertEqual(row.path.count, points.count + 2, label)
                XCTAssertEqual(row.handoff.latitude, row.path[0].latitude)
                XCTAssertEqual(row.handoff.longitude, row.path[0].longitude)
            }
        }
    }

    /// The tbm930 log starts on 118.300, flickers to 131.575 and comes back: the same
    /// frequency twice, with segments that have no points (parked), which is the case
    /// the point assignment has to get right
    func testPointsBySegmentRepeatedFrequency() throws {
        let organizer = try XCTUnwrap(FrequencyIndexOrganizer(db: try XCTUnwrap(self.db)))
        let log = try self.parsedLog(.tbm930)
        let index = try XCTUnwrap(organizer.logIndex(flightLog: log))
        let rows = try XCTUnwrap(log.frequencyScanRows())

        // ground truth: rebuild which run each point came from, as FrequencyScan.index does
        let constants = FrequencyScan.Constants.standard
        let runs = FrequencyScan.debounce(FrequencyScan.runs(rows.com1), time: rows.time, minDwell: constants.minDwell)
        XCTAssertEqual(runs.count, index.segments.count)
        var expected : [Int] = []
        for run in runs {
            expected.append(stride(from: run.first, through: run.last, by: constants.step).filter { rows.gs[$0] >= constants.minGroundSpeed }.count)
        }
        let grouped = FrequencyTimeline.pointsBySegment(segments: index.segments, points: index.points)
        XCTAssertEqual(grouped.map { $0.count }, expected)
        XCTAssertEqual(index.segments.first?.freq, index.segments.dropFirst(2).first?.freq)
    }

    func testViewModel() throws {
        let organizer = try XCTUnwrap(FrequencyIndexOrganizer(db: try XCTUnwrap(self.db)))
        let log = try self.parsedLog(.flight3)
        let index = try XCTUnwrap(organizer.logIndex(flightLog: log))

        let model = FrequencyTimelineViewModel()
        XCTAssertEqual(model.state, .idle)

        // a load finishing after another flight was selected is ignored
        model.startLoading(logFileName: "other.csv")
        model.update(index: index)
        XCTAssertEqual(model.state, .loading)
        XCTAssertTrue(model.rows.isEmpty)

        model.startLoading(logFileName: index.logFileName)
        model.update(index: index)
        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.rows.count, index.segments.count)
        XCTAssertEqual(model.totalDuration, index.segments.reduce(0.0) { $0 + $1.duration }, accuracy: 1e-6)

        model.toggle(2)
        XCTAssertEqual(model.selectedRow?.number, 2)
        model.toggle(2)
        XCTAssertNil(model.selected)

        XCTAssertEqual(FrequencyTimeline.format(duration: 65), "1:05")
        XCTAssertEqual(FrequencyTimeline.format(duration: 3725), "1:02:05")
    }
}
