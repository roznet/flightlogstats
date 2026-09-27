//
//  TestFrequencyModel.swift
//  FlightLogStatsTests
//
//  Parity of the Swift Frequency Bingo model with the Python reference.
//
//  TestAssets/freq_fixture.json is exported by
//      python -m flightreconcile.freq_cli --dir ../flightlogstatsTests/TestAssets \
//          fixture ../flightlogstatsTests/TestAssets/freq_fixture.json
//  and carries the Python scan of the test logs, its point index and its expected
//  answers. Regenerate it after any change to freq.py, never edit it by hand.
//

import XCTest
@testable import FlightLogStats
import CoreLocation
import FMDB
import RZUtils

private struct FrequencyFixture : Decodable {
    struct Constants : Decodable {
        let step : Int
        let min_dwell_s : Double
        let min_gs_kt : Double
        let alt_nm_per_1000ft : Double
        let dir_penalty_nm : Double
        let k : Int
        let soften_nm : Double
        let blend : Double
        let climb_nm_per_1000ft : Double
    }
    struct Segment : Decodable {
        let file : String
        let freq : String
        let dur_s : Double
        let nm : Double?
        let prev : String?
        let next : String?
    }
    struct Guess : Decodable {
        let freq : String
        let prob : Double
        let support : Int
        let nm : Double?
    }
    struct Answers : Decodable {
        let current : [Guess]
        let next : [Guess]
        let next_no_current : [Guess]
        let when : Double?
    }
    struct Query : Decodable {
        let lat : Double
        let lon : Double
        let alt : Double
        let trk : Double?
        let file : String
        let on : String
        let all : Answers
        let held_out : Answers
    }
    struct Rung : Decodable {
        let freq : String
        let from : Double
        let to : Double
        let confidence : Double
        let support : Int
        let alt : Double
        let alternates : [String]
        let unsettled : Bool
    }
    struct Route : Decodable {
        let file : String
        let points : [[Double]]
        let cruise : Double
        let rungs : [Rung]
    }
    struct Live : Decodable {
        let lat : Double
        let lon : Double
        let alt : Double
        let trk : Double
        let from_index : Int
        let rejoin : Int?
        let rungs : [Rung]
    }

    let constants : Constants
    let files : [String]
    let freqs : [String]
    let segments : [Segment]
    /// lat, lon, alt, trk, gs, freq index, next index (-1 none), nm to next (null none), flight index
    let points : [[Double?]]
    let queries : [Query]
    let routes : [Route]
    let live : Live

    static func load() -> FrequencyFixture? {
        guard let url = Bundle(for: EmptyClass.self).url(forResource: "freq_fixture", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        do {
            return try JSONDecoder().decode(FrequencyFixture.self, from: data)
        }catch{
            XCTFail("Failed to decode freq_fixture.json \(error)")
            return nil
        }
    }

    /// The fixture's corpus as the index would hold it
    var logs : [FrequencyLogIndex] {
        var points : [Int:[FrequencyPoint]] = [:]
        for p in self.points {
            guard p.count == 9,
                  let lat = p[0], let lon = p[1], let alt = p[2], let trk = p[3], let gs = p[4],
                  let fi = p[5], let ni = p[6], let fl = p[8]
            else {
                XCTFail("malformed fixture point \(p)")
                continue
            }
            let next : String? = ni >= 0 ? self.freqs[Int(ni)] : nil
            points[Int(fl), default: []].append(FrequencyPoint(lat: lat, lon: lon, alt: alt, trk: trk, gs: gs,
                                                               freq: self.freqs[Int(fi)], nextFreq: next,
                                                               nmToNext: p[7]))
        }
        var segments : [String:[FrequencySegment]] = [:]
        for s in self.segments {
            segments[s.file, default: []].append(FrequencySegment(freq: s.freq, logFileName: s.file, logDate: nil,
                                                                  start: nil, duration: s.dur_s, nm: s.nm ?? 0.0,
                                                                  latIn: 0.0, lonIn: 0.0, altIn: 0.0, trkIn: 0.0,
                                                                  latOut: 0.0, lonOut: 0.0, altOut: 0.0,
                                                                  prevFreq: s.prev, nextFreq: s.next, waypointIn: ""))
        }
        return self.files.enumerated().map { (fl, name) in
            FrequencyLogIndex(logFileName: name, logDate: nil, segments: segments[name] ?? [], points: points[fl] ?? [])
        }
    }
}

final class TestFrequencyModel: XCTestCase {

    //MARK: - helpers

    private func assertGuesses(_ actual : [FrequencyGuess], _ expected : [FrequencyFixture.Guess], checkNm : Bool, _ label : String) {
        XCTAssertEqual(actual.count, expected.count, "\(label): \(actual.map { $0.freq }) vs \(expected.map { $0.freq })")
        for (a, e) in zip(actual, expected) {
            XCTAssertEqual(a.prob, e.prob, accuracy: 1e-6, "\(label) \(a.freq)")
            guard a.freq == e.freq else {
                // two frequencies with the same probability may come in either order
                XCTAssertEqual(a.prob, e.prob, accuracy: 1e-9, "\(label): \(a.freq) vs \(e.freq) is only acceptable as a tie")
                continue
            }
            XCTAssertEqual(a.support, e.support, "\(label) \(a.freq) support")
            if checkNm {
                if let enm = e.nm {
                    XCTAssertNotNil(a.nmToChange, "\(label) \(a.freq) nm")
                    XCTAssertEqual(a.nmToChange ?? .nan, enm, accuracy: 1e-4, "\(label) \(a.freq) nm")
                }else{
                    XCTAssertNil(a.nmToChange, "\(label) \(a.freq) nm")
                }
            }
        }
    }

    private func assertRungs(_ actual : [FrequencyModel.Rung], _ expected : [FrequencyFixture.Rung], _ label : String) {
        XCTAssertEqual(actual.map { $0.freq }, expected.map { $0.freq }, label)
        guard actual.count == expected.count else { return }
        for (a, e) in zip(actual, expected) {
            XCTAssertEqual(a.fromNm, e.from, accuracy: 1e-5, "\(label) \(a.freq) from")
            XCTAssertEqual(a.toNm, e.to, accuracy: 1e-5, "\(label) \(a.freq) to")
            XCTAssertEqual(a.confidence, e.confidence, accuracy: 1e-6, "\(label) \(a.freq) confidence")
            XCTAssertEqual(a.support, e.support, "\(label) \(a.freq) support")
            XCTAssertEqual(a.alt, e.alt, accuracy: 1e-3, "\(label) \(a.freq) alt")
            XCTAssertEqual(a.alternates, e.alternates, "\(label) \(a.freq) alternates")
            XCTAssertEqual(a.unsettled, e.unsettled, "\(label) \(a.freq) unsettled")
        }
    }

    //MARK: - tests

    /// The constants are tuned in freq.py: a change on one side only is drift
    func testFrequencyConstants() throws {
        let fixture = try XCTUnwrap(FrequencyFixture.load())
        let scan = FrequencyScan.Constants.standard
        let model = FrequencyModel.Constants.standard
        XCTAssertEqual(scan.step, fixture.constants.step)
        XCTAssertEqual(scan.minDwell, fixture.constants.min_dwell_s)
        XCTAssertEqual(scan.minGroundSpeed, fixture.constants.min_gs_kt)
        XCTAssertEqual(model.altNmPer1000ft, fixture.constants.alt_nm_per_1000ft)
        XCTAssertEqual(model.dirPenaltyNm, fixture.constants.dir_penalty_nm)
        XCTAssertEqual(model.neighbours, fixture.constants.k)
        XCTAssertEqual(model.softenNm, fixture.constants.soften_nm)
        XCTAssertEqual(model.blendTransition, fixture.constants.blend)
        XCTAssertEqual(model.climbNmPer1000ft, fixture.constants.climb_nm_per_1000ft)
    }

    func testFrequencyDebounce() {
        let values = ["118.300"] + Array(repeating: "131.575", count: 5) + Array(repeating: "118.300", count: 100)
            + Array(repeating: "125.825", count: 2) + Array(repeating: "129.075", count: 70) + ["121.500"]
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let time = (0..<values.count).map { start.addingTimeInterval(Double($0)) }
        let runs = FrequencyScan.runs(values)
        XCTAssertEqual(runs.count, 6)
        let debounced = FrequencyScan.debounce(runs, time: time, minDwell: 60.0)
        // the flicker on 131.575 and 125.825 goes, the 118.300 either side merges, and the
        // first and last runs stay however short: they are the ground frequencies
        XCTAssertEqual(debounced.map { $0.freq }, ["118.300", "129.075", "121.500"])
        XCTAssertEqual(debounced.first?.first, 0)
        XCTAssertEqual(debounced.first?.last, 105)

        XCTAssertEqual(FrequencyGeo.angleDiff(10, 350), 20, accuracy: 1e-9)
        XCTAssertEqual(FrequencyGeo.angleDiff(350, 10), -20, accuracy: 1e-9)
        XCTAssertEqual(FrequencyGeo.angleDiff(0, 180), 180, accuracy: 1e-9)
    }

    /// The Swift scan of the test logs finds the same segments as the Python one
    func testFrequencyScanParity() throws {
        let fixture = try XCTUnwrap(FrequencyFixture.load())
        var expected : [String:[FrequencyFixture.Segment]] = [:]
        for s in fixture.segments {
            expected[s.file, default: []].append(s)
        }
        var pointsPerFile : [Int:Int] = [:]
        for p in fixture.points {
            if let fl = p[8] {
                pointsPerFile[Int(fl), default: 0] += 1
            }
        }

        for (fl, name) in fixture.files.enumerated() {
            let base = (name as NSString).deletingPathExtension
            guard let url = Bundle(for: EmptyClass.self).url(forResource: base, withExtension: "csv"),
                  let log = FlightLogFile(url: url)
            else {
                XCTFail("missing test log \(name)")
                continue
            }
            log.parse()
            let rows = try XCTUnwrap(log.frequencyScanRows(), name)
            let index = FrequencyScan.index(logFileName: name, rows: rows)
            let want = expected[name] ?? []

            XCTAssertEqual(index.segments.map { $0.freq }, want.map { $0.freq }, name)
            if index.segments.count == want.count {
                for (a, e) in zip(index.segments, want) {
                    XCTAssertEqual(a.duration, e.dur_s, accuracy: 2.0, "\(name) \(a.freq) duration")
                    XCTAssertEqual(a.nm, e.nm ?? 0.0, accuracy: 0.1 + 0.01 * a.nm, "\(name) \(a.freq) nm")
                    XCTAssertEqual(a.prevFreq, e.prev, name)
                    XCTAssertEqual(a.nextFreq, e.next, name)
                }
            }
            // the two csv readers may disagree on the odd malformed row, which can shift
            // the sampling by a row, but not the number of points to speak of
            let wantPoints = pointsPerFile[fl] ?? 0
            XCTAssertEqual(Double(index.points.count), Double(wantPoints), accuracy: max(2.0, 0.02 * Double(wantPoints)), name)
            log.clear()
        }
    }

    /// The model, on the fixture's own corpus, gives the Python answers
    func testFrequencyModelParity() throws {
        let fixture = try XCTUnwrap(FrequencyFixture.load())
        let model = FrequencyModel(logs: fixture.logs)
        XCTAssertEqual(model.count, fixture.points.count)
        XCTAssertEqual(Set(model.freqs), Set(fixture.freqs))
        XCTAssertGreaterThan(fixture.queries.count, 20)

        for (qi, q) in fixture.queries.enumerated() {
            for (tag, exclude, answers) in [("all", nil, q.all), ("held_out", q.file, q.held_out)] as [(String, String?, FrequencyFixture.Answers)] {
                let label = "query \(qi) \(tag)"
                assertGuesses(model.current(lat: q.lat, lon: q.lon, alt: q.alt, trk: q.trk, excluding: exclude),
                              answers.current, checkNm: true, "\(label) current")
                assertGuesses(model.next(lat: q.lat, lon: q.lon, alt: q.alt, trk: q.trk, current: q.on, excluding: exclude),
                              answers.next, checkNm: false, "\(label) next")
                assertGuesses(model.next(lat: q.lat, lon: q.lon, alt: q.alt, trk: q.trk, excluding: exclude),
                              answers.next_no_current, checkNm: false, "\(label) next without current")
                let when = model.when(lat: q.lat, lon: q.lon, alt: q.alt, trk: q.trk, excluding: exclude)
                if let expected = answers.when {
                    XCTAssertEqual(when ?? .nan, expected, accuracy: 1e-5, "\(label) when")
                }else{
                    XCTAssertNil(when, "\(label) when")
                }
            }
        }
    }

    func testFrequencyLadderParity() throws {
        let fixture = try XCTUnwrap(FrequencyFixture.load())
        let model = FrequencyModel(logs: fixture.logs)
        XCTAssertEqual(fixture.routes.count, 2)
        for expected in fixture.routes {
            let points = expected.points.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
            let rungs = model.routeLadder(points: points, cruiseAlt: expected.cruise)
            XCTAssertGreaterThan(rungs.count, 3)
            assertRungs(rungs, expected.rungs, "route \(expected.file)")
        }
        // the second route has a stretch with no settled answer: it must stay a band
        // of its own carrying its candidates, never be absorbed by a confident rung
        XCTAssertTrue(fixture.routes.last?.rungs.contains { $0.unsettled } ?? false)

        let first = try XCTUnwrap(fixture.routes.first)
        let route = first.points.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }

        let live = fixture.live
        let (liveRungs, rejoin) = model.liveLadder(points: route, lat: live.lat, lon: live.lon, alt: live.alt,
                                                   trk: live.trk, fromIndex: live.from_index)
        XCTAssertEqual(rejoin, live.rejoin)
        assertRungs(liveRungs, live.rungs, "live")

        // off route, a waypoint already passed is never a rejoin candidate
        XCTAssertGreaterThanOrEqual(FrequencyModel.rejoinIndex(route, lat: live.lat, lon: live.lon,
                                                                trk: live.trk, fromIndex: 4) ?? 0, 4)
    }

    /// Incremental update, delete by log file name, persistence, and rebuild on a
    /// version change rather than silently disabling the index
    func testFrequencyIndexOrganizer() throws {
        let dbname = "test_frequencyIndex.db"
        RZFileOrganizer.removeEditableFile(dbname)
        let db = FMDatabase(path: RZFileOrganizer.writeableFilePath(dbname))
        db.open()
        defer {
            db.close()
            RZFileOrganizer.removeEditableFile(dbname)
        }

        let organizer = try XCTUnwrap(FrequencyIndexOrganizer(db: db))
        XCTAssertEqual(organizer.indexedCount, 0)

        let samples : [TestLogFileSamples] = [.flight3, .diamond, .taxiOnly]
        for sample in samples {
            let url = try XCTUnwrap(sample.url)
            let log = try XCTUnwrap(FlightLogFile(url: url))
            log.parse()
            organizer.insertOrReplace(flightLog: log)
            // twice is a replace, not a duplicate
            organizer.insertOrReplace(flightLog: log)
            log.clear()
        }
        XCTAssertEqual(organizer.indexedCount, samples.count)
        for sample in samples {
            XCTAssertTrue(organizer.isIndexed(logFileName: sample.rawValue + ".csv"))
        }

        let logs = organizer.logs()
        // the taxi only log is recorded, so not retried, but carries no signal
        XCTAssertEqual(logs.map { $0.logFileName }, [TestLogFileSamples.flight3, .diamond].map { $0.rawValue + ".csv" }.sorted())
        let points = logs.reduce(0) { $0 + $1.points.count }
        XCTAssertGreaterThan(points, 100)

        let model = organizer.model()
        XCTAssertEqual(model.count, points)
        XCTAssertEqual(model.files.count, 2)
        let segments = try XCTUnwrap(logs.first?.segments)
        XCTAssertFalse(model.segments(for: segments[0].freq).isEmpty)

        organizer.delete(logFileName: TestLogFileSamples.diamond.rawValue + ".csv")
        XCTAssertFalse(organizer.isIndexed(logFileName: TestLogFileSamples.diamond.rawValue + ".csv"))
        XCTAssertEqual(organizer.logs().count, 1)
        XCTAssertLessThan(organizer.model().count, points)

        // reopening keeps what was indexed
        let reopened = try XCTUnwrap(FrequencyIndexOrganizer(db: db))
        XCTAssertEqual(reopened.indexedCount, 2)

        // a version change drops and rebuilds: empty, but not disabled
        XCTAssertTrue(db.executeUpdate("UPDATE freq_config SET version = 0", withArgumentsIn: []))
        let rebuilt = FrequencyIndexOrganizer(db: db)
        XCTAssertNotNil(rebuilt)
        XCTAssertEqual(rebuilt?.indexedCount, 0)
    }
}
