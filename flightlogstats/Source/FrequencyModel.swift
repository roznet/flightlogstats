//
//  FrequencyModel.swift
//  FlightLogStats
//
//  Frequency Bingo: predict the ATC frequency from past logs.
//
//  Port of python/flightreconcile/freq.py, which is the reference: its
//  `freq_cli eval` harness is where the constants were tuned and where any
//  model change should be justified. TestFrequencyModel replays a fixture
//  exported from it (freq_cli fixture) so the two cannot drift.
//
//  Design: designs/future/frequency-bingo.md
//

import Foundation
import CoreLocation

/// One guess, always with the number of past flights backing it: a probability
/// alone overstates when the corpus is thin.
struct FrequencyGuess {
    let freq : String
    let prob : Double
    let support : Int
    /// mean track miles to the next change over the neighbours that agree, nil if unknown
    let nmToChange : Double?
}

/// One continuous period on a single COM1 frequency, after debouncing.
struct FrequencySegment {
    let freq : String
    let logFileName : String
    /// start of the log the segment belongs to
    let logDate : Date?
    let start : Date?
    let duration : TimeInterval
    /// track miles flown while on this frequency
    let nm : Double
    let latIn : Double
    let lonIn : Double
    let altIn : Double
    let trkIn : Double
    let latOut : Double
    let lonOut : Double
    let altOut : Double
    let prevFreq : String?
    let nextFreq : String?
    let waypointIn : String
}

/// One sample of the point index, every `step` rows of a log.
struct FrequencyPoint {
    let lat : Double
    let lon : Double
    let alt : Double
    let trk : Double
    let gs : Double
    let freq : String
    let nextFreq : String?
    /// track miles until the change to `nextFreq`, nil when there is none
    let nmToNext : Double?
}

/// Everything the index keeps for one log.
struct FrequencyLogIndex {
    let logFileName : String
    let logDate : Date?
    let segments : [FrequencySegment]
    let points : [FrequencyPoint]
}

//MARK: - Scanning

enum FrequencyScan {

    /// Tuned constants, see the design doc. Change them in freq.py's eval harness, not by feel.
    struct Constants {
        /// rows (seconds, logs are 1 Hz) between indexed points
        var step : Int = 15
        /// shorter frequency runs are radio flicker, not a handoff
        var minDwell : TimeInterval = 60.0
        /// below this we are parked
        var minGroundSpeed : Double = 15.0

        static let standard = Constants()
    }

    /// The columns the index needs from one log, rows without a COM1 or a position already dropped
    struct Rows {
        var logDate : Date? = nil
        var time : [Date] = []
        var com1 : [String] = []
        var lat : [Double] = []
        var lon : [Double] = []
        var alt : [Double] = []
        var trk : [Double] = []
        var gs : [Double] = []
        var waypoint : [String] = []

        var count : Int { return self.time.count }

        mutating func append(time : Date, com1 : String, lat : Double, lon : Double, alt : Double, trk : Double, gs : Double, waypoint : String){
            self.time.append(time)
            self.com1.append(com1)
            self.lat.append(lat)
            self.lon.append(lon)
            self.alt.append(alt)
            self.trk.append(trk)
            self.gs.append(gs)
            self.waypoint.append(waypoint)
        }
    }

    struct Run : Equatable {
        let freq : String
        let first : Int
        let last : Int
    }

    /// Run-length encode a sequence
    static func runs(_ values : [String]) -> [Run] {
        var rv : [Run] = []
        guard !values.isEmpty else { return rv }
        var start = 0
        for i in 1...values.count {
            if i == values.count || values[i] != values[start] {
                rv.append(Run(freq: values[start], first: start, last: i - 1))
                start = i
            }
        }
        return rv
    }

    /// Drop runs shorter than `minDwell` and merge equal neighbours.
    ///
    /// A standby swap made and undone is a one second run; roughly a tenth of raw runs
    /// are this flicker and would otherwise look like handoffs. The first and last run
    /// are kept regardless: they are the ground frequencies, short only because the log
    /// starts or stops there.
    static func debounce(_ runs : [Run], time : [Date], minDwell : TimeInterval) -> [Run] {
        var merged : [Run] = []
        for (i, run) in runs.enumerated() {
            let keep = i == 0 || i == runs.count - 1 || time[run.last].timeIntervalSince(time[run.first]) >= minDwell
            guard keep else { continue }
            if let last = merged.last, last.freq == run.freq {
                merged[merged.count - 1] = Run(freq: run.freq, first: last.first, last: run.last)
            }else{
                merged.append(run)
            }
        }
        return merged
    }

    /// Cumulative great circle track distance in nm
    static func cumulativeNm(lat : [Double], lon : [Double]) -> [Double] {
        var rv : [Double] = []
        rv.reserveCapacity(lat.count)
        var total = 0.0
        for i in 0..<lat.count {
            if i > 0 {
                total += FrequencyGeo.haversineNm(lat[i-1], lon[i-1], lat[i], lon[i])
            }
            rv.append(total)
        }
        return rv
    }

    /// Segments and thinned points for one log. Logs too short, or whose radio never
    /// changed, carry no signal and come back with no segments and no points.
    static func index(logFileName : String, rows : Rows, constants : Constants = .standard) -> FrequencyLogIndex {
        let empty = FrequencyLogIndex(logFileName: logFileName, logDate: rows.logDate, segments: [], points: [])
        guard rows.count >= 60 else { return empty }
        let runs = self.debounce(self.runs(rows.com1), time: rows.time, minDwell: constants.minDwell)
        guard runs.count >= 2 else { return empty }

        let cum = self.cumulativeNm(lat: rows.lat, lon: rows.lon)
        var segments : [FrequencySegment] = []
        var points : [FrequencyPoint] = []

        for (j, run) in runs.enumerated() {
            let (i0, i1) = (run.first, run.last)
            let next : String? = j + 1 < runs.count ? runs[j + 1].freq : nil
            segments.append(FrequencySegment(freq: run.freq,
                                             logFileName: logFileName,
                                             logDate: rows.logDate,
                                             start: rows.time[i0],
                                             duration: rows.time[i1].timeIntervalSince(rows.time[i0]),
                                             nm: cum[i1] - cum[i0],
                                             latIn: rows.lat[i0], lonIn: rows.lon[i0],
                                             altIn: rows.alt[i0], trkIn: rows.trk[i0],
                                             latOut: rows.lat[i1], lonOut: rows.lon[i1], altOut: rows.alt[i1],
                                             prevFreq: j > 0 ? runs[j - 1].freq : nil,
                                             nextFreq: next,
                                             waypointIn: rows.waypoint[i0]))
            // every step-th sample of the run, annotated with what comes next
            for i in stride(from: i0, through: i1, by: max(1, constants.step)) {
                if rows.gs[i] < constants.minGroundSpeed {
                    continue
                }
                points.append(FrequencyPoint(lat: rows.lat[i], lon: rows.lon[i], alt: rows.alt[i],
                                             trk: rows.trk[i], gs: rows.gs[i],
                                             freq: run.freq, nextFreq: next,
                                             nmToNext: next != nil ? cum[i1] - cum[i] : nil))
            }
        }
        return FrequencyLogIndex(logFileName: logFileName, logDate: rows.logDate, segments: segments, points: points)
    }
}

//MARK: - Geometry

enum FrequencyGeo {
    /// mean earth radius in nautical miles, as in freq.py's geo module
    static let earthRadiusNm = 6371.0088 / 1.852

    static func radians(_ deg : Double) -> Double { return deg * Double.pi / 180.0 }
    static func degrees(_ rad : Double) -> Double { return rad * 180.0 / Double.pi }

    static func haversineNm(_ lat1 : Double, _ lon1 : Double, _ lat2 : Double, _ lon2 : Double) -> Double {
        let p1 = radians(lat1)
        let p2 = radians(lat2)
        let dphi = radians(lat2 - lat1)
        let dlmb = radians(lon2 - lon1)
        let a = sin(dphi / 2) * sin(dphi / 2) + cos(p1) * cos(p2) * sin(dlmb / 2) * sin(dlmb / 2)
        return 2 * earthRadiusNm * asin(min(1.0, max(0.0, a).squareRoot()))
    }

    /// Initial true bearing, 0-360
    static func initialBearing(_ lat1 : Double, _ lon1 : Double, _ lat2 : Double, _ lon2 : Double) -> Double {
        let p1 = radians(lat1)
        let p2 = radians(lat2)
        let dl = radians(lon2 - lon1)
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        return (degrees(atan2(y, x)) + 360.0).truncatingRemainder(dividingBy: 360.0)
    }

    /// Smallest signed difference a-b in degrees, in (-180, 180]
    static func angleDiff(_ a : Double, _ b : Double) -> Double {
        // python's % is a floored modulo, truncatingRemainder is not
        var m = (a - b + 180.0).truncatingRemainder(dividingBy: 360.0)
        if m < 0 {
            m += 360.0
        }
        let d = m - 180.0
        return d <= -180.0 ? d + 360.0 : d
    }

    /// Latitude/longitude to (east, north) nautical miles about (lat0, lon0)
    static func project(lat : Double, lon : Double, lat0 : Double, lon0 : Double) -> (x : Double, y : Double) {
        return ((lon - lon0) * 60.0 * cos(radians(lat0)), (lat - lat0) * 60.0)
    }
}

//MARK: - Model

/// Blend of a spatial neighbour vote and a frequency transition table.
///
/// 1. Where you are: the K nearest logged points vote for their frequency, weighted
///    1/(d + soften), with altitude and direction folded into the distance d.
/// 2. What you are on: P(next | current), counted over the segments.
///
/// A full scan per query is sub-millisecond at the corpus sizes involved and the
/// metric is not Euclidean, so there is deliberately no spatial index.
final class FrequencyModel {

    struct Constants {
        /// 1000 ft of altitude difference costs this many nm
        var altNmPer1000ft : Double = 6.0
        /// flying the exact opposite way costs this many nm
        var dirPenaltyNm : Double = 25.0
        var neighbours : Int = 60
        /// neighbour weight is 1/(distance + softenNm)
        var softenNm : Double = 2.0
        /// weight of the transition table vs the spatial vote
        var blendTransition : Double = 0.4
        /// route climb/descent gradient, track nm per 1000 ft
        var climbNmPer1000ft : Double = 2.0

        static let standard = Constants()
    }

    /// One predicted frequency along a route
    struct Rung {
        var freq : String
        var fromNm : Double
        var toNm : Double
        var confidence : Double
        var support : Int
        var alt : Double
        var alternates : [String] = []
        /// no clear winner over this stretch: the alternates are all plausible
        var unsettled : Bool = false
    }

    let constants : Constants

    /// distinct frequencies, in first seen order
    let freqs : [String]
    /// log file names of the flights in the corpus
    let files : [String]
    let segments : [FrequencySegment]

    private let freqIndex : [String:Int]
    private let fileIndex : [String:Int]

    // point index, columnar
    private let lat : [Double]
    private let lon : [Double]
    private let alt : [Double]
    private let nmToNext : [Double]   // nan when there is no next frequency
    private let freqI : [Int]
    private let nextI : [Int]         // -1 when there is no next frequency
    private let flight : [Int]

    // local flat projection in nm, and track unit vectors
    private let lat0 : Double
    private let lon0 : Double
    private let x : [Double]
    private let y : [Double]
    private let tx : [Double]
    private let ty : [Double]

    /// points of flights kept by the recency filter, nil when all are kept
    private let mask : [Bool]?

    private struct FlightFreq : Hashable {
        let flight : Int
        let freq : Int
    }
    private var transitions : [Int:[Int:Double]] = [:]
    private var transitionsByFlight : [FlightFreq:[Int:Double]] = [:]

    var count : Int { return self.lat.count }
    var isEmpty : Bool { return self.lat.isEmpty }

    /// - Parameters:
    ///   - logs: the indexed logs, logs without segments are ignored
    ///   - since: only use flights on or after this date. Airspace is reorganised and frequencies
    ///     renumber, so old flights can be confidently wrong. Ignored if it would exclude everything.
    init(logs : [FrequencyLogIndex], since : Date? = nil, constants : Constants = .standard){
        self.constants = constants

        var freqs : [String] = []
        var freqIndex : [String:Int] = [:]
        func freqId(_ f : String) -> Int {
            if let i = freqIndex[f] {
                return i
            }
            freqIndex[f] = freqs.count
            freqs.append(f)
            return freqs.count - 1
        }

        var files : [String] = []
        var fileIndex : [String:Int] = [:]
        var fileDates : [Date?] = []
        var segments : [FrequencySegment] = []

        var lat : [Double] = [], lon : [Double] = [], alt : [Double] = [], trk : [Double] = []
        var nmToNext : [Double] = [], freqI : [Int] = [], nextI : [Int] = [], flight : [Int] = []

        for log in logs {
            guard !log.segments.isEmpty, fileIndex[log.logFileName] == nil else { continue }
            let fl = files.count
            files.append(log.logFileName)
            fileIndex[log.logFileName] = fl
            fileDates.append(log.logDate)
            for segment in log.segments {
                _ = freqId(segment.freq)
                if let next = segment.nextFreq {
                    _ = freqId(next)
                }
                segments.append(segment)
            }
            for point in log.points {
                lat.append(point.lat)
                lon.append(point.lon)
                alt.append(point.alt)
                trk.append(point.trk)
                freqI.append(freqId(point.freq))
                nextI.append(point.nextFreq.map { freqId($0) } ?? -1)
                nmToNext.append(point.nmToNext ?? .nan)
                flight.append(fl)
            }
        }

        self.freqs = freqs
        self.freqIndex = freqIndex
        self.files = files
        self.fileIndex = fileIndex
        self.segments = segments
        self.lat = lat
        self.lon = lon
        self.alt = alt
        self.nmToNext = nmToNext
        self.freqI = freqI
        self.nextI = nextI
        self.flight = flight

        // locals: self cannot be read until every stored property is set
        let n = Double(max(1, lat.count))
        let lat0 = lat.reduce(0.0, +) / n
        let lon0 = lon.reduce(0.0, +) / n
        self.lat0 = lat0
        self.lon0 = lon0
        var x : [Double] = [], y : [Double] = [], tx : [Double] = [], ty : [Double] = []
        x.reserveCapacity(lat.count)
        y.reserveCapacity(lat.count)
        tx.reserveCapacity(lat.count)
        ty.reserveCapacity(lat.count)
        for i in 0..<lat.count {
            let p = FrequencyGeo.project(lat: lat[i], lon: lon[i], lat0: lat0, lon0: lon0)
            x.append(p.x)
            y.append(p.y)
            let r = FrequencyGeo.radians(trk[i])
            tx.append(sin(r))
            ty.append(cos(r))
        }
        self.x = x
        self.y = y
        self.tx = tx
        self.ty = ty

        // recency filter
        var keepFlight : [Bool]? = nil
        if let since = since {
            let ok = fileDates.map { date -> Bool in
                guard let date = date else { return false }
                return date >= since
            }
            if ok.contains(true) {
                keepFlight = ok
            }
        }
        if let keepFlight = keepFlight {
            self.mask = flight.map { keepFlight[$0] }
        }else{
            self.mask = nil
        }

        // transitions, in total and per flight so a flight can be subtracted again:
        // scoring a flight with its own transitions still in the table overstates
        // next frequency accuracy by several points
        for segment in segments {
            guard let next = segment.nextFreq,
                  let a = freqIndex[segment.freq],
                  let b = freqIndex[next],
                  let fl = fileIndex[segment.logFileName]
            else { continue }
            if let keepFlight = keepFlight, !keepFlight[fl] {
                continue
            }
            self.transitions[a, default: [:]][b, default: 0.0] += 1.0
            self.transitionsByFlight[FlightFreq(flight: fl, freq: a), default: [:]][b, default: 0.0] += 1.0
        }
    }

    //MARK: - neighbour search

    private func flightIndex(_ logFileName : String?) -> Int? {
        guard let logFileName = logFileName else { return nil }
        return self.fileIndex[logFileName]
    }

    /// P(next | current), optionally with one flight's own counts removed
    private func transitionProbs(current : Int, excluding : Int?) -> [Int:Double] {
        var counts = self.transitions[current] ?? [:]
        if let excluding = excluding, let own = self.transitionsByFlight[FlightFreq(flight: excluding, freq: current)] {
            for (b, n) in own {
                let left = (counts[b] ?? 0.0) - n
                if left > 0 {
                    counts[b] = left
                }else{
                    counts.removeValue(forKey: b)
                }
            }
        }
        let total = counts.values.reduce(0.0, +)
        guard total > 0 else { return [:] }
        return counts.mapValues { $0 / total }
    }

    /// the K nearest points under the model metric, in no particular order
    private func neighbours(lat : Double, lon : Double, alt : Double, trk : Double?, excluding : Int?) -> [(index : Int, distance : Double)] {
        let k = self.constants.neighbours
        guard k > 0, !self.lat.isEmpty else { return [] }
        let q = FrequencyGeo.project(lat: lat, lon: lon, lat0: self.lat0, lon0: self.lon0)
        let altW = self.constants.altNmPer1000ft
        let dirW = self.constants.dirPenaltyNm
        var sr = 0.0
        var cr = 0.0
        if let trk = trk {
            let r = FrequencyGeo.radians(trk)
            sr = sin(r)
            cr = cos(r)
        }

        var selected : [(index : Int, distance : Double)] = []
        selected.reserveCapacity(k)
        var worst = -Double.infinity
        var worstAt = -1

        for i in 0..<self.lat.count {
            if let mask = self.mask, !mask[i] {
                continue
            }
            if let excluding = excluding, self.flight[i] == excluding {
                continue
            }
            var d = hypot(self.x[i] - q.x, self.y[i] - q.y) + abs(self.alt[i] - alt) / 1000.0 * altW
            if trk != nil {
                let cosang = self.tx[i] * sr + self.ty[i] * cr
                d += (1.0 - cosang) / 2.0 * dirW
            }
            if selected.count < k {
                selected.append((i, d))
                if d > worst {
                    worst = d
                    worstAt = selected.count - 1
                }
            }else if d < worst {
                selected[worstAt] = (i, d)
                worst = -Double.infinity
                for (j, s) in selected.enumerated() where s.distance > worst {
                    worst = s.distance
                    worstAt = j
                }
            }
        }
        return selected
    }

    private static func vote(_ keys : [Int], _ weights : [Double]) -> [Int:Double] {
        var out : [Int:Double] = [:]
        for (key, w) in zip(keys, weights) where key >= 0 {
            out[key, default: 0.0] += w
        }
        let total = out.values.reduce(0.0, +)
        let norm = total != 0.0 ? total : 1.0
        return out.mapValues { $0 / norm }
    }

    /// highest first, ties broken by frequency so the order is deterministic
    private func ranked(_ probs : [Int:Double]) -> [(key : Int, value : Double)] {
        return probs.map { (key: $0.key, value: $0.value) }.sorted {
            $0.value != $1.value ? $0.value > $1.value : self.freqs[$0.key] < self.freqs[$1.key]
        }
    }

    //MARK: - public API

    /// Which frequency are you most likely on, here, at this altitude, on this track?
    /// - Parameter excluding: log file name of a flight to leave out (evaluation)
    func current(lat : Double, lon : Double, alt : Double, trk : Double? = nil, top : Int = 3, excluding : String? = nil) -> [FrequencyGuess] {
        let exclude = self.flightIndex(excluding)
        let sel = self.neighbours(lat: lat, lon: lon, alt: alt, trk: trk, excluding: exclude)
        guard !sel.isEmpty else { return [] }
        let soften = self.constants.softenNm
        let probs = Self.vote(sel.map { self.freqI[$0.index] }, sel.map { 1.0 / ($0.distance + soften) })

        var flights : [Int:Set<Int>] = [:]
        var nmSum : [Int:Double] = [:]
        var nmCount : [Int:Int] = [:]
        for s in sel {
            let fi = self.freqI[s.index]
            flights[fi, default: []].insert(self.flight[s.index])
            let nm = self.nmToNext[s.index]
            if nm.isFinite {
                nmSum[fi, default: 0.0] += nm
                nmCount[fi, default: 0] += 1
            }
        }
        return self.ranked(probs).prefix(top).map { kv -> FrequencyGuess in
            let n = nmCount[kv.key] ?? 0
            return FrequencyGuess(freq: self.freqs[kv.key], prob: kv.value,
                                  support: flights[kv.key]?.count ?? 0,
                                  nmToChange: n > 0 ? (nmSum[kv.key] ?? 0.0) / Double(n) : nil)
        }
    }

    /// Which frequency comes next, given where you are and, if known, what you are on?
    ///
    /// The spatial vote answers "what do flights around here change to", the transition
    /// table "what usually follows this frequency". The two log-probabilities are blended.
    func next(lat : Double, lon : Double, alt : Double, trk : Double? = nil, current : String? = nil, top : Int = 3, excluding : String? = nil) -> [FrequencyGuess] {
        let exclude = self.flightIndex(excluding)
        let sel = self.neighbours(lat: lat, lon: lon, alt: alt, trk: trk, excluding: exclude)
        guard !sel.isEmpty else { return [] }
        let soften = self.constants.softenNm
        let spatial = Self.vote(sel.map { self.nextI[$0.index] }, sel.map { 1.0 / ($0.distance + soften) })

        var trans : [Int:Double] = [:]
        if let current = current, let ci = self.freqIndex[current] {
            trans = self.transitionProbs(current: ci, excluding: exclude)
        }

        let a = trans.isEmpty ? 0.0 : self.constants.blendTransition
        let eps = 1e-4
        var score : [Int:Double] = [:]
        for key in Set(spatial.keys).union(trans.keys) {
            score[key] = a * log(trans[key] ?? eps) + (1.0 - a) * log(spatial[key] ?? eps)
        }
        guard let mx = score.values.max() else { return [] }
        let scaled = score.mapValues { exp($0 - mx) }
        let total = scaled.values.reduce(0.0, +)
        let norm = total != 0.0 ? total : 1.0

        var flights : [Int:Set<Int>] = [:]
        for s in sel {
            flights[self.nextI[s.index], default: []].insert(self.flight[s.index])
        }
        return self.ranked(scaled).prefix(top).map { kv -> FrequencyGuess in
            return FrequencyGuess(freq: self.freqs[kv.key], prob: kv.value / norm,
                           support: flights[kv.key]?.count ?? 0, nmToChange: nil)
        }
    }

    /// Estimated track miles until the next frequency change, nil if unknown
    func when(lat : Double, lon : Double, alt : Double, trk : Double? = nil, excluding : String? = nil) -> Double? {
        let sel = self.neighbours(lat: lat, lon: lon, alt: alt, trk: trk, excluding: self.flightIndex(excluding))
        var sum = 0.0
        var wsum = 0.0
        for s in sel {
            let nm = self.nmToNext[s.index]
            guard nm.isFinite else { continue }
            let w = 1.0 / (s.distance + self.constants.softenNm)
            sum += nm * w
            wsum += w
        }
        return wsum > 0 ? sum / wsum : nil
    }

    /// The segments behind a frequency, most recent first: each carries the log file
    /// name, the key of `FlightLogFileRecord`, so it can lead to the flight itself.
    func segments(for freq : String) -> [FrequencySegment] {
        return self.segments.filter { $0.freq == freq }.sorted {
            ($0.start ?? .distantPast) > ($1.start ?? .distantPast)
        }
    }

    /// The logged positions backing a frequency, for a scatter on the map
    func points(for freq : String) -> [CLLocationCoordinate2D] {
        guard let fi = self.freqIndex[freq] else { return [] }
        var rv : [CLLocationCoordinate2D] = []
        for i in 0..<self.lat.count where self.freqI[i] == fi {
            if let mask = self.mask, !mask[i] {
                continue
            }
            rv.append(CLLocationCoordinate2D(latitude: self.lat[i], longitude: self.lon[i]))
        }
        return rv
    }
}

//MARK: - Route ladder

extension FrequencyModel {

    struct RouteSample {
        let lat : Double
        let lon : Double
        let track : Double
        let alongNm : Double
    }

    /// Densify a route into samples roughly every `stepNm`
    static func sampleRoute(_ points : [CLLocationCoordinate2D], stepNm : Double = 4.0) -> [RouteSample] {
        var rv : [RouteSample] = []
        var total = 0.0
        if points.count > 1 {
            for (p1, p2) in zip(points, points.dropFirst()) {
                let leg = FrequencyGeo.haversineNm(p1.latitude, p1.longitude, p2.latitude, p2.longitude)
                let brg = FrequencyGeo.initialBearing(p1.latitude, p1.longitude, p2.latitude, p2.longitude)
                let n = max(1, Int(leg / stepNm))
                for i in 0..<n {
                    let f = Double(i) / Double(n)
                    rv.append(RouteSample(lat: p1.latitude + (p2.latitude - p1.latitude) * f,
                                          lon: p1.longitude + (p2.longitude - p1.longitude) * f,
                                          track: brg, alongNm: total + leg * f))
                }
                total += leg
            }
        }
        if let last = points.last {
            rv.append(RouteSample(lat: last.latitude, lon: last.longitude, track: rv.last?.track ?? 0.0, alongNm: total))
        }
        return rv
    }

    /// A crude climb, cruise, descent profile.
    ///
    /// `fieldAlt` is where the climb starts and `endAlt` where the descent finishes. They
    /// differ in live mode: the start is the current altitude (already level, no climb)
    /// while the far end is still airfield elevation. Tying them together would hold the
    /// profile at cruise to the threshold and lose every arrival frequency.
    static func altitudeProfile(alongNm : Double, totalNm : Double, cruiseAlt : Double,
                                fieldAlt : Double = 1000.0, nmPer1000ft : Double = 2.0,
                                endAlt : Double? = nil) -> Double {
        let endAlt = endAlt ?? fieldAlt
        let climb = max(0.0, (cruiseAlt - fieldAlt) / 1000.0 * nmPer1000ft)
        let descent = max(0.0, (cruiseAlt - endAlt) / 1000.0 * nmPer1000ft)
        if alongNm < climb && climb > 0 {
            return fieldAlt + (cruiseAlt - fieldAlt) * (alongNm / climb)
        }
        if alongNm > totalNm - descent && descent > 0 {
            let left = max(0.0, totalNm - alongNm)
            return endAlt + (cruiseAlt - endAlt) * (left / descent)
        }
        return cruiseAlt
    }

    /// Where we are along the route: index of the next waypoint and how far off the line
    static func routeProgress(_ points : [CLLocationCoordinate2D], lat : Double, lon : Double) -> (next : Int, offsetNm : Double) {
        guard points.count >= 2 else { return (0, 0.0) }
        let lat0 = points.map { $0.latitude }.reduce(0.0, +) / Double(points.count)
        let lon0 = points.map { $0.longitude }.reduce(0.0, +) / Double(points.count)
        let p = FrequencyGeo.project(lat: lat, lon: lon, lat0: lat0, lon0: lon0)
        var bestI = 1
        var bestD = Double.infinity
        for i in 0..<(points.count - 1) {
            let a = FrequencyGeo.project(lat: points[i].latitude, lon: points[i].longitude, lat0: lat0, lon0: lon0)
            let b = FrequencyGeo.project(lat: points[i+1].latitude, lon: points[i+1].longitude, lat0: lat0, lon0: lon0)
            let vx = b.x - a.x
            let vy = b.y - a.y
            let seg2 = vx * vx + vy * vy
            let t = seg2 == 0 ? 0.0 : max(0.0, min(1.0, ((p.x - a.x) * vx + (p.y - a.y) * vy) / seg2))
            let d = hypot(p.x - (a.x + t * vx), p.y - (a.y + t * vy))
            if d < bestD {
                bestD = d
                bestI = i + 1
            }
        }
        return (bestI, bestD)
    }

    /// Index of the route waypoint we would next be sent direct to.
    ///
    /// Off route, assume the IFR outcome: you rejoin at the next fix you are actually
    /// flying towards. Candidates start at the next waypoint along the route (bearing alone
    /// nominated the departure airport when flying south from mid route), and the first
    /// within `coneDeg` of the track wins. Nothing ahead (a hold, a 180) falls back to the
    /// next one along. `fromIndex` is the furthest waypoint reached, so progress is monotonic.
    static func rejoinIndex(_ points : [CLLocationCoordinate2D], lat : Double, lon : Double, trk : Double?,
                            coneDeg : Double = 100.0, fromIndex : Int = 0) -> Int? {
        guard !points.isEmpty else { return nil }
        let next = self.routeProgress(points, lat: lat, lon: lon).next
        let start = max(fromIndex, min(next, points.count - 1))
        guard start < points.count else { return nil }
        if let trk = trk {
            for i in start..<points.count {
                let brg = FrequencyGeo.initialBearing(lat, lon, points[i].latitude, points[i].longitude)
                if abs(FrequencyGeo.angleDiff(brg, trk)) <= coneDeg / 2.0 {
                    return i
                }
            }
        }
        return start
    }

    /// Predict the frequency sequence along a route, in order.
    ///
    /// Walks the route asking "which frequency here", collapses runs of the same answer,
    /// and never lets a confident rung absorb an uncertain stretch: runs of short
    /// unconvincing rungs become a band of their own, marked unsettled, carrying their
    /// candidates and their low confidence. Overstating is the one thing this cannot do.
    func routeLadder(points : [CLLocationCoordinate2D], cruiseAlt : Double, stepNm : Double = 4.0,
                     minRungNm : Double = 8.0, fieldAlt : Double = 1000.0,
                     climbNmPer1000ft : Double? = nil, endAlt : Double? = nil) -> [Rung] {
        let samples = Self.sampleRoute(points, stepNm: stepNm)
        guard let totalNm = samples.last?.alongNm else { return [] }
        let gradient = climbNmPer1000ft ?? self.constants.climbNmPer1000ft

        var rungs : [Rung] = []
        for sample in samples {
            let alt = Self.altitudeProfile(alongNm: sample.alongNm, totalNm: totalNm, cruiseAlt: cruiseAlt,
                                           fieldAlt: fieldAlt, nmPer1000ft: gradient, endAlt: endAlt)
            let guesses = self.current(lat: sample.lat, lon: sample.lon, alt: alt, trk: sample.track, top: 3)
            guard let top = guesses.first else { continue }
            if let last = rungs.last, last.freq == top.freq {
                let i = rungs.count - 1
                rungs[i].toNm = sample.alongNm
                rungs[i].confidence = max(last.confidence, top.prob)
                rungs[i].support = max(last.support, top.support)
            }else{
                rungs.append(Rung(freq: top.freq, fromNm: sample.alongNm, toNm: sample.alongNm,
                                  confidence: top.prob, support: top.support, alt: alt,
                                  alternates: guesses.dropFirst().map { $0.freq }))
            }
        }

        // Approach and tower sectors are only a few miles of route and are the ones worth
        // knowing, so a short rung survives when the vote is clear and several flights back it
        func solid(_ r : Rung) -> Bool {
            return r.confidence >= 0.6 && r.support >= 5
        }
        func long(_ r : Rung) -> Bool {
            return (r.toNm - r.fromNm) >= minRungNm
        }

        var merged : [Rung] = []
        var i = 0
        while i < rungs.count {
            let r = rungs[i]
            // the first rung is the departure frequency: always kept, however brief
            if i == 0 || long(r) || solid(r) {
                if let last = merged.last, last.freq == r.freq {
                    merged[merged.count - 1].toNm = r.toNm
                }else{
                    merged.append(r)
                }
                i += 1
                continue
            }

            var group : [Rung] = []
            while i < rungs.count {
                let rj = rungs[i]
                if long(rj) || solid(rj) {
                    break
                }
                group.append(rj)
                i += 1
            }
            guard let first = group.first, let lastOfGroup = group.last else { continue }

            var order : [String] = []   // first seen order, for stable ties
            var span : [String:Double] = [:]
            var weighted : [String:Double] = [:]
            for g in group {
                let w = max(g.toNm - g.fromNm, stepNm)
                if span[g.freq] == nil {
                    order.append(g.freq)
                }
                span[g.freq, default: 0.0] += w
                weighted[g.freq, default: 0.0] += w * g.confidence
            }
            let spanTotal = order.reduce(0.0) { $0 + (span[$1] ?? 0.0) }
            let bandSpan = spanTotal != 0.0 ? spanTotal : 1.0
            let ranked = order.enumerated().sorted {
                let s0 = span[$0.element] ?? 0.0
                let s1 = span[$1.element] ?? 0.0
                return s0 != s1 ? s0 > s1 : $0.offset < $1.offset
            }.map { $0.element }
            let best = ranked[0]
            let band = Rung(freq: best, fromNm: first.fromNm, toNm: lastOfGroup.toNm,
                            confidence: (weighted[best] ?? 0.0) / bandSpan,
                            support: group.filter { $0.freq == best }.map { $0.support }.max() ?? 0,
                            alt: first.alt,
                            alternates: Array(ranked.dropFirst().prefix(2)),
                            unsettled: ranked.count > 1)
            if let last = merged.last, last.freq == band.freq, !band.unsettled {
                merged[merged.count - 1].toNm = band.toNm
            }else{
                merged.append(band)
            }
        }

        // each rung runs to where the prediction flips, so the ladder has no gaps
        if merged.count > 1 {
            for j in 0..<(merged.count - 1) {
                merged[j].toNm = merged[j + 1].fromNm
            }
        }
        if !merged.isEmpty {
            merged[merged.count - 1].toNm = totalNm
        }
        return merged
    }

    /// The ladder ahead from where you actually are.
    ///
    /// The route becomes the current position then the route from the rejoin waypoint on,
    /// fed to the same ladder: off route is not a special mode. Distances are from the
    /// current position, and the profile starts at the current altitude, so a level
    /// aircraft gets no phantom climb, only the descent at the far end.
    ///
    /// - Returns: the rungs and the rejoin index, to pass back as `fromIndex` next time
    func liveLadder(points : [CLLocationCoordinate2D], lat : Double, lon : Double, alt : Double, trk : Double?,
                    cruiseAlt : Double? = nil, fromIndex : Int = 0, stepNm : Double = 4.0,
                    minRungNm : Double = 8.0, destinationAlt : Double = 1000.0) -> (rungs : [Rung], rejoinIndex : Int?) {
        guard let rejoin = Self.rejoinIndex(points, lat: lat, lon: lon, trk: trk, fromIndex: fromIndex) else {
            return ([], nil)
        }
        let route = [CLLocationCoordinate2D(latitude: lat, longitude: lon)] + points[rejoin...]
        guard route.count >= 2 else { return ([], rejoin) }
        let cruise : Double
        if let cruiseAlt = cruiseAlt, cruiseAlt != 0 {
            cruise = cruiseAlt
        }else{
            cruise = alt
        }
        let rungs = self.routeLadder(points: route, cruiseAlt: cruise, stepNm: stepNm, minRungNm: minRungNm,
                                     fieldAlt: alt, endAlt: destinationAlt)
        return (rungs, rejoin)
    }
}
