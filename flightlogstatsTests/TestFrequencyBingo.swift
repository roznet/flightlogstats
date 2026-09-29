//
//  TestFrequencyBingo.swift
//  FlightLogStatsTests
//
//  Frequency Bingo: the radio's tap rules, current -> rung selection, storage as
//  FlightExchange, the route of a flown flight and its ladder, and live mode (GPS
//  fixes, the handoff ahead, the live ladder from a point of a flown flight).
//
//  Design: designs/future/frequency-bingo.md §Implementing plan mode
//

import XCTest
@testable import FlightLogStats
import CoreLocation
import FMDB
import RZFlight

final class TestFrequencyBingo: XCTestCase {

    private var directory : URL! = nil

    override func setUpWithError() throws {
        self.directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestFrequencyBingo-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: self.directory)
    }

    //MARK: - helpers

    private typealias Rung = FrequencyModel.Rung

    /// A straight west to east route along 46N, one rung per 10 nm stretch
    private func bingoRungs(_ rungs : [Rung]) -> [BingoRung] {
        return rungs.enumerated().map { item in
            let coordinate = CLLocationCoordinate2D(latitude: 46.0, longitude: 7.0 + Double(item.offset) * 0.2)
            return BingoRung(number: item.offset + 1, rung: item.element, handoff: coordinate, track: 90.0,
                             path: [coordinate, CLLocationCoordinate2D(latitude: 46.0, longitude: coordinate.longitude + 0.2)])
        }
    }

    private func sampleRungs() -> [Rung] {
        return [
            Rung(freq: "118.275", fromNm: 0, toNm: 13, confidence: 1.0, support: 40, alt: 1000),
            Rung(freq: "119.175", fromNm: 13, toNm: 72, confidence: 0.91, support: 12, alt: 7565,
                 alternates: ["126.350", "125.550"]),
            Rung(freq: "125.415", fromNm: 72, toNm: 137, confidence: 0.64, support: 5, alt: 11000,
                 alternates: ["124.105", "126.990"]),
            Rung(freq: "118.890", fromNm: 137, toNm: 230, confidence: 1.0, support: 6, alt: 11000,
                 alternates: ["124.105", "125.415"]),
        ]
    }

    private func viewModel(store : BingoStore? = nil, launch : BingoLaunch = BingoLaunch()) -> FrequencyBingoViewModel {
        return FrequencyBingoViewModel(launch: launch, store: store) { nil }
    }

    private func route(_ names : [(String, Double, Double)], cruise : Int? = nil) -> Route {
        let first = names[0]
        let last = names[names.count - 1]
        let middle = names.dropFirst().dropLast()
        return Route(departure: first.0, destination: last.0,
                     waypoints: middle.map { $0.0 },
                     departureCoords: [first.1, first.2],
                     destinationCoords: [last.1, last.2],
                     waypointCoords: middle.map { RoutePoint(name: $0.0, latitude: $0.1, longitude: $0.2) },
                     cruiseAltitudeFt: cruise)
    }

    private func navResolver() throws -> (RoutePointResolver, KnownAirports) {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "nav", withExtension: "db"))
        let db = FMDatabase(url: url)
        XCTAssertTrue(db.open())
        let airports = KnownAirports(db: db)
        return (RoutePointResolver(airports: airports, waypoints: KnownWaypoints(db: db)), airports)
    }

    //MARK: - radio

    /// Every row of the tap table: whatever becomes current pushes the old current
    /// into previous; previous flip-flops
    func testRadioRules() {
        var radio = BingoRadio()
        XCTAssertNil(radio.current)
        XCTAssertNil(radio.previous)

        // nothing to flip back to
        radio.flip()
        XCTAssertNil(radio.current)

        radio.set("118.275")
        XCTAssertEqual(radio, BingoRadio(current: "118.275", previous: nil))
        radio.set("119.175")
        XCTAssertEqual(radio, BingoRadio(current: "119.175", previous: "118.275"))
        // the same again changes nothing: previous is not lost
        radio.set("119.175")
        XCTAssertEqual(radio, BingoRadio(current: "119.175", previous: "118.275"))

        radio.flip()
        XCTAssertEqual(radio, BingoRadio(current: "118.275", previous: "119.175"))
        radio.flip()
        XCTAssertEqual(radio, BingoRadio(current: "119.175", previous: "118.275"))
    }

    /// The tap table on the screen's model: next, previous, a rung, an "also likely",
    /// and a current on no rung
    func testTapRules() {
        let model = self.viewModel()
        model.apply(rungs: self.bingoRungs(self.sampleRungs()))
        XCTAssertNil(model.selected)
        XCTAssertNil(model.radio.current)

        // a rung of the table: current, and selected
        model.tapRung(2)
        XCTAssertEqual(model.radio, BingoRadio(current: "119.175", previous: nil))
        XCTAssertEqual(model.selected, 1)

        // a next candidate: current, old current to previous, selection follows
        model.tapNext(FrequencyGuess(freq: "125.415", prob: 0.6, support: 5, nmToChange: nil))
        XCTAssertEqual(model.radio, BingoRadio(current: "125.415", previous: "119.175"))
        XCTAssertEqual(model.selected, 2)

        // previous: flip-flop, back to the rung before
        model.flip()
        XCTAssertEqual(model.radio, BingoRadio(current: "119.175", previous: "125.415"))
        XCTAssertEqual(model.selected, 1)
        model.flip()
        XCTAssertEqual(model.selected, 2)

        // an "also likely": current, and that rung selected
        model.tapAlternate("124.105", rung: 4)
        XCTAssertEqual(model.radio, BingoRadio(current: "124.105", previous: "125.415"))
        XCTAssertEqual(model.selected, 3)

        // a current on no rung keeps the selection where it was
        model.makeCurrent("121.500")
        XCTAssertEqual(model.radio, BingoRadio(current: "121.500", previous: "124.105"))
        XCTAssertEqual(model.selected, 3)

        // out of range taps do nothing
        model.tapRung(0)
        model.tapRung(9)
        XCTAssertEqual(model.radio.current, "121.500")
        XCTAssertEqual(model.selected, 3)
    }

    /// Current -> rung: first at or after the selected one, then the nearest before,
    /// then the same over the alternates; nil keeps the selection
    func testCurrentSelectsRung() {
        let rungs = self.sampleRungs()
        XCTAssertEqual(FrequencyBingo.rungIndex(for: "118.275", in: rungs, from: nil), 0)
        XCTAssertEqual(FrequencyBingo.rungIndex(for: "125.415", in: rungs, from: nil), 2)
        // a rung's own frequency wins over an alternate further on, and over one before
        XCTAssertEqual(FrequencyBingo.rungIndex(for: "125.415", in: rungs, from: 3), 2)
        // alternates only when no rung has it: 124.105 is an alternate of 3 and 4
        XCTAssertEqual(FrequencyBingo.rungIndex(for: "124.105", in: rungs, from: nil), 2)
        XCTAssertEqual(FrequencyBingo.rungIndex(for: "124.105", in: rungs, from: 3), 3)
        XCTAssertEqual(FrequencyBingo.rungIndex(for: "126.350", in: rungs, from: 3), 1)
        XCTAssertNil(FrequencyBingo.rungIndex(for: "121.500", in: rungs, from: 2))
        XCTAssertNil(FrequencyBingo.rungIndex(for: "118.275", in: [], from: nil))

        // the same frequency twice on the route: the one at or after the selection
        var twice = rungs
        twice.append(Rung(freq: "118.275", fromNm: 230, toNm: 240, confidence: 1.0, support: 3, alt: 1000))
        XCTAssertEqual(FrequencyBingo.rungIndex(for: "118.275", in: twice, from: 2), 4)
        XCTAssertEqual(FrequencyBingo.rungIndex(for: "118.275", in: twice, from: 0), 0)
    }

    /// Next never offers current, and shows a second candidate only on a near tie
    func testNextCandidates() {
        func guess(_ freq : String, _ prob : Double) -> FrequencyGuess {
            return FrequencyGuess(freq: freq, prob: prob, support: 3, nmToChange: nil)
        }
        XCTAssertEqual(FrequencyBingo.nextCandidates([], current: nil).count, 0)
        // the 60/40 boundary: both
        XCTAssertEqual(FrequencyBingo.nextCandidates([guess("132.100", 0.6), guess("118.890", 0.4)], current: nil).map { $0.freq },
                       ["132.100", "118.890"])
        // a clear winner: never a filler second
        XCTAssertEqual(FrequencyBingo.nextCandidates([guess("132.100", 0.9), guess("118.890", 0.1)], current: nil).map { $0.freq },
                       ["132.100"])
        // current is dropped, the rest move up
        XCTAssertEqual(FrequencyBingo.nextCandidates([guess("118.890", 0.5), guess("132.100", 0.3), guess("124.105", 0.2)],
                                                     current: "118.890").map { $0.freq },
                       ["132.100", "124.105"])
    }

    //MARK: - live

    /// CoreLocation's invalid values (negative accuracy or course) become nil
    func testLiveFix() {
        let coordinate = CLLocationCoordinate2D(latitude: 46.0, longitude: 7.0)
        let good = BingoFix(location: CLLocation(coordinate: coordinate, altitude: 3048.0, horizontalAccuracy: 5,
                                                 verticalAccuracy: 10, course: 270.0, courseAccuracy: 5,
                                                 speed: 61.73, speedAccuracy: 1, timestamp: Date()))
        XCTAssertEqual(try XCTUnwrap(good.altitudeFt), 10000.0, accuracy: 0.1)
        XCTAssertEqual(good.track, 270.0)
        XCTAssertEqual(try XCTUnwrap(good.groundSpeedKt), 120.0, accuracy: 0.1)
        XCTAssertTrue(good.isAirborne)

        let bad = BingoFix(location: CLLocation(coordinate: coordinate, altitude: 3048.0, horizontalAccuracy: 5,
                                                verticalAccuracy: -1, course: -1, courseAccuracy: -1,
                                                speed: -1, speedAccuracy: -1, timestamp: Date()))
        XCTAssertNil(bad.altitudeFt)
        XCTAssertNil(bad.track)
        XCTAssertNil(bad.groundSpeedKt)
        XCTAssertFalse(bad.isAirborne)
    }

    /// On the ground the climb to the plan's cruise is still ahead; in the air the
    /// current altitude is both, so there is no phantom climb
    func testLiveAltitudes() {
        let coordinate = CLLocationCoordinate2D(latitude: 46.0, longitude: 7.0)
        let ground = BingoFix(coordinate: coordinate, altitudeFt: 1600, track: nil, groundSpeedKt: 10)
        XCTAssertTrue(FrequencyBingo.liveAltitudes(fix: ground, plannedFt: 11000) == (1600, 11000))
        let noAltitude = BingoFix(coordinate: coordinate, altitudeFt: nil, track: nil, groundSpeedKt: nil)
        XCTAssertTrue(FrequencyBingo.liveAltitudes(fix: noAltitude, plannedFt: 11000) == (FrequencyBingo.fieldAltitudeFt, 11000))
        // descending through 4000 on an 11000 ft plan: no climb back to cruise
        let descending = BingoFix(coordinate: coordinate, altitudeFt: 4000, track: 90, groundSpeedKt: 120)
        XCTAssertTrue(FrequencyBingo.liveAltitudes(fix: descending, plannedFt: 11000) == (4000, 4000))
        let airborneNoAltitude = BingoFix(coordinate: coordinate, altitudeFt: nil, track: 90, groundSpeedKt: 120)
        XCTAssertTrue(FrequencyBingo.liveAltitudes(fix: airborneNoAltitude, plannedFt: 11000) == (11000, 11000))
    }

    /// The handoff is the end of the current frequency's rung ahead; a current on no
    /// rung ahead is due
    func testHandoff() throws {
        let rungs = self.sampleRungs()
        XCTAssertNil(FrequencyBingo.handoff([], current: nil, groundSpeedKt: 120))

        // no current: the first change along the ladder, 13 nm at 120 kt is 6.5 min
        let first = try XCTUnwrap(FrequencyBingo.handoff(rungs, current: nil, groundSpeedKt: 120))
        XCTAssertEqual(first.nm, 13)
        XCTAssertEqual(try XCTUnwrap(first.minutes), 6.5, accuracy: 1e-9)
        XCTAssertFalse(first.due)
        // too slow for an ETA
        XCTAssertNil(try XCTUnwrap(FrequencyBingo.handoff(rungs, current: nil, groundSpeedKt: 10)).minutes)

        XCTAssertEqual(FrequencyBingo.handoff(rungs, current: "118.275", groundSpeedKt: nil)?.nm, 13)
        // switched early, on the next rung's frequency: its end, not due
        XCTAssertEqual(FrequencyBingo.handoff(rungs, current: "119.175", groundSpeedKt: nil)?.nm, 72)
        // the last rung's frequency holds to the end: no handoff
        XCTAssertNil(FrequencyBingo.handoff(rungs, current: "118.890", groundSpeedKt: nil))
        // on no rung ahead: the rung it belonged to ended behind, due
        let due = try XCTUnwrap(FrequencyBingo.handoff(rungs, current: "121.500", groundSpeedKt: 120))
        XCTAssertTrue(due.due)
        XCTAssertEqual(due.nm, 0)

        // a candidate of a band with no clear winner counts as its rung; a plain alternate does not
        var banded = rungs
        banded[0] = Rung(freq: "118.275", fromNm: 0, toNm: 13, confidence: 0.4, support: 3, alt: 1000,
                         alternates: ["120.000"], unsettled: true)
        XCTAssertEqual(FrequencyBingo.handoff(banded, current: "120.000", groundSpeedKt: nil)?.nm, 13)
        XCTAssertEqual(FrequencyBingo.handoff(rungs, current: "126.350", groundSpeedKt: nil)?.due, true)
    }

    //MARK: - storage

    /// current.json holds a FlightExchange RZFlight decodes unchanged, plus the radio;
    /// recent.json up to 10, most recent first, deduplicated on the route string
    func testStorageRoundTrip() throws {
        let store = BingoStore(directory: self.directory)
        XCTAssertNil(store.loadCurrent())
        XCTAssertEqual(store.loadRecent().count, 0)

        let route = self.route([("LSGS", 46.2196, 7.3267), ("DJL", 47.2713, 5.0947),
                                ("REM", 49.3106, 4.0453), ("EGTF", 51.3481, -0.5594)])
        let model = self.viewModel(store: store, launch: BingoLaunch(route: route, cruiseAltitudeFt: 11000, source: .menu))
        XCTAssertEqual(model.routeText, "LSGS DJL REM EGTF")
        XCTAssertEqual(model.cruiseAltitudeFt, 11000)
        model.apply(rungs: self.bingoRungs(self.sampleRungs()))
        model.tapRung(3)
        model.tapRung(4)
        model.setCruiseAltitude(11500)

        // the stored flight decodes with RZFlight's own decoder, as another flyfun app would
        let data = try Data(contentsOf: store.currentURL)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String:Any])
        let flightJson = try XCTUnwrap(json["flight"])
        let exchange = try FlightExchange.decode(from: try JSONSerialization.data(withJSONObject: flightJson))
        XCTAssertEqual(exchange.schemaVersion, FlightExchange.currentSchemaVersion)
        XCTAssertEqual(exchange.source?.app, "flightlogstats")
        XCTAssertEqual(exchange.route.departure, "LSGS")
        XCTAssertEqual(exchange.route.destination, "EGTF")
        XCTAssertEqual(exchange.route.waypoints, ["DJL", "REM"])
        XCTAssertEqual(exchange.route.waypointCoords.map { $0.name }, ["DJL", "REM"])
        XCTAssertEqual(exchange.route.cruiseAltitudeFt, 11500)
        XCTAssertEqual(exchange.route.allCoordinates.count, 4)
        XCTAssertEqual(try XCTUnwrap(exchange.route.departureCoordinate).latitude, 46.2196, accuracy: 1e-9)

        // relaunching from the menu restores route, altitude, radio and selection
        let restored = self.viewModel(store: store)
        XCTAssertEqual(restored.routeText, "LSGS DJL REM EGTF")
        XCTAssertEqual(restored.cruiseAltitudeFt, 11500)
        XCTAssertEqual(restored.radio, BingoRadio(current: "118.890", previous: "125.415"))
        XCTAssertEqual(restored.selected, 3)
        XCTAssertEqual(restored.routePoints.count, 4)

        // a flight whose route could not be built opens empty, but keeps the radio
        let fromFlight = self.viewModel(store: store, launch: BingoLaunch(source: .flight(logFileName: "log_x.csv")))
        XCTAssertNil(fromFlight.route)
        XCTAssertEqual(fromFlight.radio.current, "118.890")

        // recent: most recent first, deduplicated, capped
        for i in 0..<12 {
            store.addRecent(FrequencyBingo.exchange(self.route([("EGTF", 51.3, -0.5), ("W\(i)", 50.0, 0.0), ("LFAT", 50.5, 1.6)])))
        }
        store.addRecent(FrequencyBingo.exchange(self.route([("EGTF", 51.3, -0.5), ("W5", 50.0, 0.0), ("LFAT", 50.5, 1.6)])))
        let recent = store.loadRecent()
        XCTAssertEqual(recent.count, BingoStore.recentCount)
        XCTAssertEqual(recent.map { FrequencyBingo.routeString($0.route) }.first, "EGTF W5 LFAT")
        XCTAssertEqual(Set(recent.map { FrequencyBingo.routeString($0.route) }).count, recent.count)
        XCTAssertFalse(recent.contains { $0.route.departure == "LSGS" })

        // each element is a plain FlightExchange too
        let recentJson = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: store.recentURL)) as? [Any])
        for element in recentJson {
            XCTAssertNoThrow(try FlightExchange.decode(from: try JSONSerialization.data(withJSONObject: element)))
        }
    }

    //MARK: - route geometry

    /// A cut of the route runs exactly between the two along-track distances
    func testRouteCut() throws {
        let points = [CLLocationCoordinate2D(latitude: 46.0, longitude: 7.0),
                      CLLocationCoordinate2D(latitude: 46.0, longitude: 7.5),
                      CLLocationCoordinate2D(latitude: 46.5, longitude: 7.5)]
        let leg1 = FrequencyGeo.haversineNm(46.0, 7.0, 46.0, 7.5)
        let leg2 = FrequencyGeo.haversineNm(46.0, 7.5, 46.5, 7.5)
        let total = leg1 + leg2

        func length(_ path : [CLLocationCoordinate2D]) -> Double {
            return zip(path, path.dropFirst()).reduce(0.0) {
                $0 + FrequencyGeo.haversineNm($1.0.latitude, $1.0.longitude, $1.1.latitude, $1.1.longitude)
            }
        }

        let whole = FrequencyBingo.cut(points, fromNm: 0, toNm: total)
        XCTAssertEqual(whole.count, 3)
        XCTAssertEqual(length(whole), total, accuracy: 1e-6)

        // across the corner: starts mid leg 1, keeps the corner, ends mid leg 2
        let across = FrequencyBingo.cut(points, fromNm: leg1 / 2, toNm: leg1 + leg2 / 2)
        XCTAssertEqual(across.count, 3)
        XCTAssertEqual(across[0].longitude, 7.25, accuracy: 1e-9)
        XCTAssertEqual(across[1].longitude, 7.5, accuracy: 1e-9)
        XCTAssertEqual(across[2].latitude, 46.25, accuracy: 1e-9)
        XCTAssertEqual(length(across), leg1 / 2 + leg2 / 2, accuracy: 0.05)

        XCTAssertEqual(FrequencyBingo.track(points, atNm: 1.0), 90.0, accuracy: 0.5)
        XCTAssertEqual(FrequencyBingo.track(points, atNm: leg1 + 1.0), 0.0, accuracy: 0.5)
    }

    //MARK: - route from a flown flight

    func testRouteString() {
        XCTAssertEqual(FrequencyBingo.routeString(departure: "lsgs", destination: "EGTF",
                                                  waypoints: ["LSGS", "SAPRE", "SAPRE", "DJL", "REM", "REM", "EGTF"]),
                       "LSGS SAPRE DJL REM EGTF")
        XCTAssertEqual(FrequencyBingo.routeString(departure: "EGTF", destination: "EGTF", waypoints: []), "EGTF EGTF")
        XCTAssertNil(FrequencyBingo.routeString(departure: nil, destination: "EGTF", waypoints: ["DJL"]))
        XCTAssertEqual(FrequencyBingo.tokens("lsgs dct DJL -> rem,EGTF"), ["LSGS", "DJL", "REM", "EGTF"])

        XCTAssertNil(FrequencyBingo.cruiseAltitude(altitudes: []))
        // the 90th percentile, not the maximum: a brief climb above cruise is ignored
        let altitudes = Array(repeating: 1000.0, count: 10) + Array(repeating: 10930.0, count: 80) + [16000.0]
        XCTAssertEqual(FrequencyBingo.cruiseAltitude(altitudes: altitudes), 11000)
    }

    /// The route of a TestAssets flight resolves, and a ladder over it is non-empty,
    /// ordered, and covers it from 0 to its length
    func testRouteFromFlightAndLadder() throws {
        let (resolver, airports) = try self.navResolver()

        var logs : [FrequencyLogIndex] = []
        var flight : FlightLogFile? = nil
        for sample in [TestLogFileSamples.flight2, .flight3, .diamond, .tbm930] {
            let log = try XCTUnwrap(FlightLogFile(url: try XCTUnwrap(sample.url)))
            log.parse()
            let rows = try XCTUnwrap(log.frequencyScanRows())
            logs.append(FrequencyScan.index(logFileName: sample.rawValue + ".csv", rows: rows))
            if sample == .flight3 {
                flight = log
            }
        }
        let log = try XCTUnwrap(flight)
        let summary = try XCTUnwrap(log.flightSummary)
        let rows = try XCTUnwrap(log.frequencyScanRows())

        // the airports the summary finds, looked up here so the test does not depend on
        // AppDelegate having loaded them
        let departure = try XCTUnwrap(airports.nearestAirport(coord: CLLocationCoordinate2D(latitude: try XCTUnwrap(rows.lat.first),
                                                                                             longitude: try XCTUnwrap(rows.lon.first))))
        let destination = try XCTUnwrap(airports.nearestAirport(coord: CLLocationCoordinate2D(latitude: try XCTUnwrap(rows.lat.last),
                                                                                               longitude: try XCTUnwrap(rows.lon.last))))
        let cruise = try XCTUnwrap(FrequencyBingo.cruiseAltitude(altitudes: FrequencyBingo.flyingAltitudes(rows: rows, flying: summary.flying)))
        XCTAssertEqual(cruise % FrequencyBingo.altitudeStep, 0)
        XCTAssertGreaterThan(cruise, 0)
        XCTAssertLessThanOrEqual(Double(cruise), try XCTUnwrap(rows.alt.max()) + 250.0)

        let launch = FrequencyBingo.launch(logFileName: "flight3.csv", departure: departure.icao, destination: destination.icao,
                                           waypoints: summary.route.map { $0.name }, cruiseAltitudeFt: cruise, resolver: resolver)
        let route = try XCTUnwrap(launch.route)
        XCTAssertEqual(route.departure, departure.icao)
        XCTAssertEqual(route.destination, destination.icao)
        XCTAssertEqual(route.cruiseAltitudeFt, cruise)
        XCTAssertNotEqual(route.waypoints.first, departure.icao)
        for (a, b) in zip(route.waypoints, route.waypoints.dropFirst()) {
            XCTAssertNotEqual(a, b, "consecutive duplicate")
        }
        let points = route.allCoordinates
        XCTAssertGreaterThanOrEqual(points.count, 2)
        let total = zip(points, points.dropFirst()).reduce(0.0) {
            $0 + FrequencyGeo.haversineNm($1.0.latitude, $1.0.longitude, $1.1.latitude, $1.1.longitude)
        }
        XCTAssertGreaterThan(total, 5.0)

        let model = FrequencyModel(logs: logs)
        let rungs = FrequencyBingo.rungs(model: model, points: points, cruiseAlt: Double(cruise))
        guard !rungs.isEmpty else {
            return XCTFail("no rung over the route of \(route)")
        }
        XCTAssertEqual(rungs.map { $0.number }, Array(1...rungs.count))
        XCTAssertEqual(try XCTUnwrap(rungs.first).rung.fromNm, 0.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(rungs.last).rung.toNm, total, accuracy: 1e-6)
        for (a, b) in zip(rungs, rungs.dropFirst()) {
            XCTAssertEqual(a.rung.toNm, b.rung.fromNm, accuracy: 1e-9)
            XCTAssertLessThan(a.rung.fromNm, b.rung.fromNm)
        }
        for rung in rungs {
            XCTAssertGreaterThanOrEqual(rung.path.count, 1)
            XCTAssertLessThanOrEqual(rung.rung.fromNm, rung.rung.toNm)
            XCTAssertTrue(model.freqs.contains(rung.freq))
        }

        // live, from a point halfway through the flight: the ladder starts at the
        // position and runs to the end of the route from the rejoin fix
        let mid = rows.lat.count / 2
        let fix = BingoFix(coordinate: CLLocationCoordinate2D(latitude: rows.lat[mid], longitude: rows.lon[mid]),
                           altitudeFt: rows.alt[mid], track: rows.trk[mid], groundSpeedKt: 120)
        let (liveRungs, rejoin) = FrequencyBingo.liveRungs(model: model, points: points, fix: fix,
                                                           plannedFt: cruise, fromIndex: 0)
        let rejoinIndex = try XCTUnwrap(rejoin)
        XCTAssertGreaterThanOrEqual(rejoinIndex, 1)
        XCTAssertLessThan(rejoinIndex, points.count)
        let ahead = [fix.coordinate] + points[rejoinIndex...]
        let aheadNm = zip(ahead, ahead.dropFirst()).reduce(0.0) {
            $0 + FrequencyGeo.haversineNm($1.0.latitude, $1.0.longitude, $1.1.latitude, $1.1.longitude)
        }
        let firstLive = try XCTUnwrap(liveRungs.first)
        XCTAssertEqual(firstLive.rung.fromNm, 0.0, accuracy: 1e-9)
        XCTAssertEqual(firstLive.handoff.latitude, fix.coordinate.latitude, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(liveRungs.last).rung.toNm, aheadNm, accuracy: 1e-6)
        // the rejoin floor keeps progress monotonic
        XCTAssertGreaterThanOrEqual(FrequencyBingo.liveRungs(model: model, points: points, fix: fix, plannedFt: cruise,
                                                             fromIndex: points.count - 1).rejoinIndex ?? 0,
                                    points.count - 1)

        // the screen's model: a fix switches to live, nil back to the plan ladder
        let screen = self.viewModel(launch: BingoLaunch(route: route, cruiseAltitudeFt: cruise, source: .menu))
        screen.update(model: model)
        self.wait(for: [self.until { !screen.computing && !screen.rungs.isEmpty }], timeout: 60)
        XCTAssertFalse(screen.isLive)
        XCTAssertEqual(screen.rungs.count, rungs.count)

        screen.update(live: fix)
        XCTAssertTrue(screen.isLive)
        self.wait(for: [self.until { !screen.computing && screen.rungs.first?.handoff.latitude == fix.coordinate.latitude }], timeout: 60)
        XCTAssertEqual(screen.rungs.count, liveRungs.count)
        XCTAssertEqual(screen.rejoinFloor, rejoinIndex)
        XCTAssertEqual(screen.selected, 0)
        if liveRungs.count > 1 {
            XCTAssertEqual(try XCTUnwrap(screen.handoff).nm, liveRungs[1].rung.fromNm, accuracy: 1e-9)
        }
        // a current on no rung ahead: the handoff is due at once, before the next fix
        screen.makeCurrent("121.500")
        XCTAssertEqual(screen.handoff?.due, true)

        screen.update(live: nil)
        XCTAssertFalse(screen.isLive)
        XCTAssertNil(screen.handoff)
        self.wait(for: [self.until { !screen.computing && !screen.rungs.isEmpty }], timeout: 60)
        XCTAssertEqual(try XCTUnwrap(screen.rungs.last).rung.toNm, total, accuracy: 1e-6)
    }

    /// Fulfilled once the condition holds, checked on the main run loop
    private func until(_ condition : @escaping () -> Bool) -> XCTestExpectation {
        return XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
    }
}
