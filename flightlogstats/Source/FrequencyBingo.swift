//
//  FrequencyBingo.swift
//  FlightLogStats
//
//  Frequency Bingo plan mode: a route and a cruise altitude give the ladder of
//  frequencies to expect, and a radio (current / previous / next) the pilot
//  drives, like a COM active/standby pair. The pilot's current is the model's
//  `current` input; the model never changes it.
//
//  Pure (Foundation, CoreLocation, RZFlight, Observation): no AppDelegate or
//  Settings. The screen and its hosting controller are in FrequencyBingoView.swift.
//
//  Design: designs/future/frequency-bingo.md §The page
//

import Foundation
import CoreLocation
import Observation
import OSLog
import RZFlight

//MARK: - Launch

/// The only way into the Bingo screen, so anything with a route can open it
/// without reaching into its state.
struct BingoLaunch {
    enum Source {
        /// the log list menu: the last route, or empty
        case menu
        /// "Bingo this route" from a flown flight
        case flight(logFileName : String)
        /// follow-on: FlyFun Weather, Autorouter, ICAO FPL
        case imported(FlightExchange.Source?)
    }

    /// nil opens the last route, or an empty route field
    var route : Route? = nil
    /// defaults to `route.cruiseAltitudeFt`, then the last used
    var cruiseAltitudeFt : Int? = nil
    var source : Source = .menu
}

//MARK: - Radio

/// Current and previous, as the pilot set them. Every change goes through one rule:
/// whatever becomes current pushes the old current into previous.
struct BingoRadio : Codable, Equatable {
    private(set) var current : String? = nil
    private(set) var previous : String? = nil

    init(current : String? = nil, previous : String? = nil) {
        self.current = current
        self.previous = previous
    }

    /// A next candidate, a table frequency or a typed one becomes current.
    /// Setting the frequency already current changes nothing, so previous is not lost.
    mutating func set(_ freq : String) {
        guard freq != self.current else { return }
        self.previous = self.current
        self.current = freq
    }

    /// Flip-flop: current and previous swap. Nothing to swap back to, nothing happens.
    mutating func flip() {
        guard self.previous != nil else { return }
        swap(&self.current, &self.previous)
    }
}

//MARK: - Ladder rows

/// One rung of the ladder as the screen shows it: numbered like the map markers,
/// with the stretch of route it covers.
struct BingoRung : Identifiable {
    /// 1-based, the number on the map marker
    let number : Int
    var id : Int { return self.number }
    let rung : FrequencyModel.Rung
    /// where the rung starts: the handoff marker
    let handoff : CLLocationCoordinate2D
    /// track at the start of the rung, from the route leg there
    let track : Double
    /// the route from `fromNm` to `toNm`
    let path : [CLLocationCoordinate2D]

    var freq : String { return self.rung.freq }
}

enum FrequencyBingo {
    /// the second next candidate is shown only when this close to the first (a 60/40
    /// boundary is 0.67): never as a filler
    static let nearTieRatio = 0.5
    /// cruise altitude when neither the launch, the route nor the last use gives one
    static let defaultCruiseAltitudeFt = 5000
    static let altitudeRange = 1000...25000
    static let altitudeStep = 500

    /// Tokens `RoutePointResolver.resolveRouteString` ignores
    static let routeNotation : Set<String> = ["DCT", "->", "TO"]

    /// Ladder rows for a route: the model's rungs, each with its piece of route
    static func rungs(model : FrequencyModel, points : [CLLocationCoordinate2D], cruiseAlt : Double) -> [BingoRung] {
        guard points.count >= 2 else { return [] }
        let ladder = model.routeLadder(points: points, cruiseAlt: cruiseAlt)
        return ladder.enumerated().compactMap { item in
            let (i, rung) = (item.offset, item.element)
            let path = self.cut(points, fromNm: rung.fromNm, toNm: rung.toNm)
            guard let first = path.first else { return nil }
            return BingoRung(number: i + 1, rung: rung, handoff: first,
                             track: self.track(points, atNm: rung.fromNm), path: path)
        }
    }

    /// The part of a route between two along-track distances, interpolated as
    /// `FrequencyModel.sampleRoute` does (haversine leg lengths, linear in lat/lon),
    /// so the cut lands where the ladder sampled.
    static func cut(_ points : [CLLocationCoordinate2D], fromNm : Double, toNm : Double) -> [CLLocationCoordinate2D] {
        guard let firstPoint = points.first else { return [] }
        guard points.count > 1 else { return [firstPoint] }

        func interpolate(_ p1 : CLLocationCoordinate2D, _ p2 : CLLocationCoordinate2D, _ f : Double) -> CLLocationCoordinate2D {
            return CLLocationCoordinate2D(latitude: p1.latitude + (p2.latitude - p1.latitude) * f,
                                          longitude: p1.longitude + (p2.longitude - p1.longitude) * f)
        }

        var rv : [CLLocationCoordinate2D] = []
        var total = 0.0
        for (p1, p2) in zip(points, points.dropFirst()) {
            let leg = FrequencyGeo.haversineNm(p1.latitude, p1.longitude, p2.latitude, p2.longitude)
            let legStart = total
            let legEnd = total + leg
            total = legEnd
            if legEnd < fromNm || legStart > toNm {
                continue
            }
            if leg == 0.0 {
                if rv.isEmpty {
                    rv.append(p1)
                }
                continue
            }
            if rv.isEmpty {
                rv.append(interpolate(p1, p2, max(0.0, (fromNm - legStart) / leg)))
            }
            if legEnd <= toNm {
                rv.append(p2)
            }else{
                rv.append(interpolate(p1, p2, (toNm - legStart) / leg))
                break
            }
        }
        if rv.isEmpty, let last = points.last {
            // past the end of the route
            rv.append(last)
        }
        return rv
    }

    /// Initial bearing of the route leg at an along-track distance
    static func track(_ points : [CLLocationCoordinate2D], atNm : Double) -> Double {
        var total = 0.0
        var last = 0.0
        for (p1, p2) in zip(points, points.dropFirst()) {
            let leg = FrequencyGeo.haversineNm(p1.latitude, p1.longitude, p2.latitude, p2.longitude)
            guard leg > 0.0 else { continue }
            last = FrequencyGeo.initialBearing(p1.latitude, p1.longitude, p2.latitude, p2.longitude)
            if atNm < total + leg {
                return last
            }
            total += leg
        }
        return last
    }

    /// Index of the rung a new current frequency belongs to, nil to keep the selection.
    ///
    /// The first rung at or after the selected one whose frequency is current, then the
    /// nearest one before it (a flip-flop back after a mistake), then the same two passes
    /// over the rungs' alternates. A current on no rung returns nil.
    static func rungIndex(for freq : String, in rungs : [FrequencyModel.Rung], from selected : Int?) -> Int? {
        guard !rungs.isEmpty else { return nil }
        let start = min(max(selected ?? 0, 0), rungs.count - 1)
        let order = Array(start..<rungs.count) + Array((0..<start).reversed())
        if let i = order.first(where: { rungs[$0].freq == freq }) {
            return i
        }
        return order.first { rungs[$0].alternates.contains(freq) }
    }

    /// Next candidates to show: the current frequency is never offered as next, and the
    /// second only when it is a near tie with the first.
    static func nextCandidates(_ guesses : [FrequencyGuess], current : String?) -> [FrequencyGuess] {
        let candidates = guesses.filter { $0.freq != current }
        guard let first = candidates.first else { return [] }
        if candidates.count > 1 && candidates[1].prob >= first.prob * self.nearTieRatio {
            return [first, candidates[1]]
        }
        return [first]
    }

    //MARK: route text

    static func tokens(_ routeString : String) -> [String] {
        return routeString.uppercased()
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "," })
            .map(String.init)
            .filter { !self.routeNotation.contains($0) }
    }

    /// The route as typed: departure, waypoints, destination
    static func routeString(_ route : Route) -> String {
        return ([route.departure] + route.waypoints + [route.destination]).joined(separator: " ")
    }

    /// Names of a route string the resolver does not know. RoutePointResolver drops them
    /// from the route silently; the screen shows them instead.
    static func unresolved(_ routeString : String, resolver : RoutePointResolver) -> [String] {
        var seen = Set<String>()
        return self.tokens(routeString).filter { resolver.resolve($0) == nil && seen.insert($0).inserted }
    }

    /// The same route with another cruise altitude: `Route` is immutable
    static func route(_ route : Route, cruiseAltitudeFt : Int) -> Route {
        var alternateCoords : [String:[Double]] = [:]
        for alternate in route.alternates {
            if let coord = route.coordinate(for: alternate) {
                alternateCoords[alternate] = [coord.latitude, coord.longitude]
            }
        }
        return Route(departure: route.departure,
                     destination: route.destination,
                     alternates: route.alternates,
                     waypoints: route.waypoints,
                     departureCoords: route.departureCoordinate.map { [$0.latitude, $0.longitude] },
                     destinationCoords: route.destinationCoordinate.map { [$0.latitude, $0.longitude] },
                     alternateCoords: alternateCoords.isEmpty ? nil : alternateCoords,
                     waypointCoords: route.waypointCoords,
                     aircraftType: route.aircraftType,
                     departureTime: route.departureTime,
                     arrivalTime: route.arrivalTime,
                     flightLevel: route.flightLevel,
                     cruiseAltitudeFt: cruiseAltitudeFt)
    }

    static func exchange(_ route : Route, flightId : String? = nil) -> FlightExchange {
        return FlightExchange(route: route,
                              name: "\(route.departure) -> \(route.destination)",
                              source: FlightExchange.Source(app: "flightlogstats", flightId: flightId))
    }

    //MARK: route from a flown flight

    /// Route string of a flown flight: departure, the active waypoints with consecutive
    /// duplicates removed and the airports at the ends dropped, destination.
    /// Nil without both a departure and a destination.
    static func routeString(departure : String?, destination : String?, waypoints : [String]) -> String? {
        guard let departure = departure?.uppercased(), !departure.isEmpty,
              let destination = destination?.uppercased(), !destination.isEmpty else { return nil }
        var middle : [String] = []
        for name in waypoints.map({ $0.uppercased().trimmingCharacters(in: .whitespaces) }) where !name.isEmpty {
            if middle.last != name {
                middle.append(name)
            }
        }
        // the flight plan usually starts at the departure and ends at the destination
        while let first = middle.first, first == departure || first == destination {
            middle.removeFirst()
        }
        while let last = middle.last, last == destination || last == departure {
            middle.removeLast()
        }
        return ([departure] + middle + [destination]).joined(separator: " ")
    }

    /// Cruise altitude of a flown flight: the 90th percentile of the altitude while
    /// flying, rounded to 500 ft. Nil without altitudes.
    static func cruiseAltitude(altitudes : [Double]) -> Int? {
        let sorted = altitudes.filter { $0.isFinite }.sorted()
        guard !sorted.isEmpty else { return nil }
        let p90 = sorted[Int((Double(sorted.count - 1) * 0.9).rounded())]
        let step = Double(self.altitudeStep)
        return Int((p90 / step).rounded() * step)
    }

    /// Altitudes of the scan rows within the flying time range, all of them if unknown
    static func flyingAltitudes(rows : FrequencyScan.Rows, flying : TimeRange?) -> [Double] {
        guard let flying = flying else { return rows.alt }
        return zip(rows.time, rows.alt).filter { $0.0 >= flying.start && $0.0 <= flying.end }.map { $0.1 }
    }

    /// Launch Bingo on the route of a flown flight
    static func launch(logFileName : String, departure : String?, destination : String?, waypoints : [String],
                       cruiseAltitudeFt : Int?, resolver : RoutePointResolver?) -> BingoLaunch {
        var launch = BingoLaunch(route: nil, cruiseAltitudeFt: cruiseAltitudeFt, source: .flight(logFileName: logFileName))
        if let resolver = resolver,
           let text = self.routeString(departure: departure, destination: destination, waypoints: waypoints),
           let route = resolver.resolveRouteString(text) {
            launch.route = cruiseAltitudeFt.map { self.route(route, cruiseAltitudeFt: $0) } ?? route
        }
        return launch
    }
}

//MARK: - Storage

/// What `current.json` keeps: the route as the flyfun apps share it, and the screen
/// state beside it, never inside it.
struct BingoState : Codable {
    var flight : FlightExchange
    var radio : BingoRadio
    /// 0-based index of the selected rung
    var selectedRung : Int?

    enum CodingKeys : String, CodingKey {
        case flight
        case radio
        case selectedRung = "selected_rung"
    }
}

/// `Application Support/FrequencyBingo/`: `current.json` and `recent.json` (up to 10
/// `FlightExchange`, most recent first, deduplicated on the route string). Not
/// `Documents/`, which is the log library mirrored to iCloud Drive.
final class BingoStore {
    static let recentCount = 10

    let directory : URL

    init(directory : URL) {
        self.directory = directory
    }

    static var standard : BingoStore {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return BingoStore(directory: base.appendingPathComponent("FrequencyBingo", isDirectory: true))
    }

    var currentURL : URL { return self.directory.appendingPathComponent("current.json") }
    var recentURL : URL { return self.directory.appendingPathComponent("recent.json") }

    /// the wire format of `FlightExchange`: ISO-8601 dates
    private static var encoder : JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
    private static var decoder : JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func loadCurrent() -> BingoState? {
        guard let data = try? Data(contentsOf: self.currentURL) else { return nil }
        do {
            return try Self.decoder.decode(BingoState.self, from: data)
        }catch{
            Logger.app.error("Bingo: could not read \(self.currentURL.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    func saveCurrent(_ state : BingoState) {
        self.write(state, to: self.currentURL)
    }

    func loadRecent() -> [FlightExchange] {
        guard let data = try? Data(contentsOf: self.recentURL) else { return [] }
        do {
            return try Self.decoder.decode([FlightExchange].self, from: data)
        }catch{
            Logger.app.error("Bingo: could not read \(self.recentURL.lastPathComponent): \(error.localizedDescription)")
            return []
        }
    }

    /// Put a route first in the recent list, and return the new list
    @discardableResult
    func addRecent(_ flight : FlightExchange) -> [FlightExchange] {
        let key = FrequencyBingo.routeString(flight.route)
        var recent = self.loadRecent().filter { FrequencyBingo.routeString($0.route) != key }
        recent.insert(flight, at: 0)
        recent = Array(recent.prefix(Self.recentCount))
        self.write(recent, to: self.recentURL)
        return recent
    }

    private func write<T : Encodable>(_ value : T, to url : URL) {
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(value)
            try data.write(to: url, options: .atomic)
        }catch{
            Logger.app.error("Bingo: could not write \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

//MARK: - View model

/// State of the Bingo screen. Main thread only; the ladder is computed on its own
/// queue and a late result for an older route or altitude is dropped.
@Observable
final class FrequencyBingoViewModel {
    enum State : Equatable {
        /// the model is being read from the index
        case loading
        /// no frequency index
        case unavailable
        case ready
    }

    private(set) var state : State = .loading
    /// what the route field shows
    var routeText : String = ""
    private(set) var route : Route? = nil
    /// names typed that are neither an airport nor a waypoint
    private(set) var unresolved : [String] = []
    private(set) var cruiseAltitudeFt : Int = FrequencyBingo.defaultCruiseAltitudeFt
    private(set) var radio = BingoRadio()
    /// 0-based index into `rungs`
    private(set) var selected : Int? = nil
    private(set) var rungs : [BingoRung] = []
    private(set) var next : [FrequencyGuess] = []
    private(set) var computing : Bool = false
    private(set) var recent : [FlightExchange] = []
    private(set) var flights : Int = 0

    var routePoints : [CLLocationCoordinate2D] { return self.route?.allCoordinates ?? [] }
    var selectedRung : BingoRung? {
        guard let selected = self.selected, selected < self.rungs.count else { return nil }
        return self.rungs[selected]
    }

    @ObservationIgnored private var model : FrequencyModel? = nil
    private let store : BingoStore?
    private let resolver : () -> RoutePointResolver?
    @ObservationIgnored private var flightId : String? = nil
    @ObservationIgnored private var generation : Int = 0
    private let queue = DispatchQueue(label: "net.ro-z.flightlogstats.bingo")

    /// - Parameters:
    ///   - store: nil keeps nothing (tests)
    ///   - resolver: airports and waypoints may still be loading when the screen opens
    init(launch : BingoLaunch, store : BingoStore?, resolver : @escaping () -> RoutePointResolver?) {
        self.store = store
        self.resolver = resolver
        let saved = store?.loadCurrent()
        self.recent = store?.loadRecent() ?? []
        // the radio is the pilot's, whatever the route: it survives leaving the screen
        self.radio = saved?.radio ?? BingoRadio()

        // the last route only from the menu: a flight whose route could not be built
        // opens empty rather than on an unrelated route
        var restoresLast = true
        if case .flight(let logFileName) = launch.source {
            self.flightId = logFileName
            restoresLast = false
        }
        if let route = launch.route {
            self.cruiseAltitudeFt = launch.cruiseAltitudeFt ?? route.cruiseAltitudeFt
                ?? saved?.flight.route.cruiseAltitudeFt ?? FrequencyBingo.defaultCruiseAltitudeFt
            self.setRoute(route)
        }else if restoresLast, let saved = saved {
            self.cruiseAltitudeFt = launch.cruiseAltitudeFt ?? saved.flight.route.cruiseAltitudeFt ?? FrequencyBingo.defaultCruiseAltitudeFt
            self.flightId = saved.flight.source?.flightId
            self.route = saved.flight.route
            self.routeText = FrequencyBingo.routeString(saved.flight.route)
            self.selected = saved.selectedRung
        }else if let altitude = launch.cruiseAltitudeFt {
            self.cruiseAltitudeFt = altitude
        }
    }

    //MARK: inputs

    /// The model from the index, on first load and whenever the index changes
    func update(model : FrequencyModel?) {
        self.model = model
        self.flights = model?.files.count ?? 0
        self.state = model == nil ? .unavailable : .ready
        self.rebuild()
    }

    /// Resolve what is in the route field
    func submitRoute() {
        let text = self.routeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let resolver = self.resolver() else {
            Logger.app.info("Bingo: airports not loaded yet")
            return
        }
        self.unresolved = FrequencyBingo.unresolved(text, resolver: resolver)
        guard let route = resolver.resolveRouteString(text) else {
            self.route = nil
            self.rungs = []
            self.selected = nil
            self.refreshNext()
            return
        }
        self.flightId = nil
        self.setRoute(route)
    }

    func select(recent flight : FlightExchange) {
        if let altitude = flight.route.cruiseAltitudeFt {
            self.cruiseAltitudeFt = altitude
        }
        self.unresolved = []
        self.flightId = flight.source?.flightId
        self.setRoute(flight.route)
    }

    func setCruiseAltitude(_ altitude : Int) {
        let clamped = min(max(altitude, FrequencyBingo.altitudeRange.lowerBound), FrequencyBingo.altitudeRange.upperBound)
        guard clamped != self.cruiseAltitudeFt else { return }
        self.cruiseAltitudeFt = clamped
        if let route = self.route {
            self.route = FrequencyBingo.route(route, cruiseAltitudeFt: clamped)
        }
        self.save()
        self.rebuild()
    }

    //MARK: the radio

    /// A next candidate becomes current
    func tapNext(_ guess : FrequencyGuess) {
        self.makeCurrent(guess.freq)
    }

    /// Flip-flop current and previous
    func flip() {
        self.radio.flip()
        self.currentChanged()
    }

    /// A rung of the table: its frequency becomes current and the rung is selected
    func tapRung(_ number : Int) {
        let index = number - 1
        guard index >= 0 && index < self.rungs.count else { return }
        self.radio.set(self.rungs[index].freq)
        self.selected = index
        self.refreshNext()
        self.save()
    }

    /// An "also likely" of a rung: it becomes current and that rung is selected
    func tapAlternate(_ freq : String, rung number : Int) {
        let index = number - 1
        guard index >= 0 && index < self.rungs.count else { return }
        self.radio.set(freq)
        self.selected = index
        self.refreshNext()
        self.save()
    }

    /// Any other way of setting current (keypad, follow-on)
    func makeCurrent(_ freq : String) {
        self.radio.set(freq)
        self.currentChanged()
    }

    private func currentChanged() {
        if let current = self.radio.current,
           let index = FrequencyBingo.rungIndex(for: current, in: self.rungs.map { $0.rung }, from: self.selected) {
            self.selected = index
        }
        self.refreshNext()
        self.save()
    }

    //MARK: computing

    private func setRoute(_ route : Route) {
        let withAltitude = FrequencyBingo.route(route, cruiseAltitudeFt: self.cruiseAltitudeFt)
        let changed = self.route.map { FrequencyBingo.routeString($0) } != FrequencyBingo.routeString(withAltitude)
        self.route = withAltitude
        self.routeText = FrequencyBingo.routeString(withAltitude)
        if changed {
            self.selected = nil
            self.rungs = []
        }
        if withAltitude.allCoordinates.count >= 2, let store = self.store {
            self.recent = store.addRecent(FrequencyBingo.exchange(withAltitude, flightId: self.flightId))
        }
        self.save()
        self.rebuild()
    }

    /// Recompute the ladder off the main thread; a late result is dropped
    private func rebuild() {
        self.generation += 1
        let generation = self.generation
        guard let model = self.model, !model.isEmpty, self.routePoints.count >= 2 else {
            self.rungs = []
            self.computing = false
            self.refreshNext()
            return
        }
        let points = self.routePoints
        let altitude = Double(self.cruiseAltitudeFt)
        self.computing = true
        self.queue.async {
            let rungs = FrequencyBingo.rungs(model: model, points: points, cruiseAlt: altitude)
            DispatchQueue.main.async {
                guard generation == self.generation else { return }
                self.apply(rungs: rungs)
            }
        }
    }

    /// Show a computed ladder, keeping the selection on the rung of the current frequency
    func apply(rungs : [BingoRung]) {
        self.rungs = rungs
        self.computing = false
        if let current = self.radio.current,
           let index = FrequencyBingo.rungIndex(for: current, in: rungs.map { $0.rung }, from: self.selected) {
            self.selected = index
        }else if let selected = self.selected, selected >= rungs.count {
            self.selected = nil
        }
        self.refreshNext()
    }

    /// Next, from the start of the selected rung (the start of the route when none is),
    /// with the pilot's current as the model's current
    private func refreshNext() {
        guard let model = self.model, !model.isEmpty else {
            self.next = []
            return
        }
        guard let rung = self.selectedRung ?? self.rungs.first else {
            self.next = []
            return
        }
        let guesses = model.next(lat: rung.handoff.latitude, lon: rung.handoff.longitude, alt: rung.rung.alt,
                                 trk: rung.track, current: self.radio.current, top: 3)
        self.next = FrequencyBingo.nextCandidates(guesses, current: self.radio.current)
    }

    private func save() {
        guard let store = self.store, let route = self.route else { return }
        store.saveCurrent(BingoState(flight: FrequencyBingo.exchange(route, flightId: self.flightId),
                                     radio: self.radio, selectedRung: self.selected))
    }
}
