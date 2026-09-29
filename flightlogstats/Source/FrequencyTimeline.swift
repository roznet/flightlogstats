//
//  FrequencyTimeline.swift
//  FlightLogStats
//
//  Per-flight frequency timeline: the debounced COM1 segments of one log, from
//  the Frequency Bingo index, as numbered rows with the track flown on each.
//  The numbers are the handoff markers on the map.
//
//  Pure (Foundation, CoreLocation, Observation): no AppDelegate or Settings, so
//  it can move to FlightLogKit with FrequencyModel.
//
//  Design: designs/future/frequency-bingo.md, designs/plans/modernisation.md §Phase 3
//

import Foundation
import CoreLocation
import Observation

/// One segment of the timeline: a continuous period on one COM1 frequency, as the
/// index recorded it. Short first and last rows are the ground frequencies, kept by
/// the debounce; nothing is smoothed further here.
struct FrequencyTimelineRow : Identifiable {
    /// 1-based position in the flight, the number drawn on the map marker
    let number : Int
    var id : Int { return self.number }

    let freq : String
    let start : Date?
    /// since the start of the log, nil if either is unknown
    let elapsed : TimeInterval?
    let duration : TimeInterval
    /// track miles flown on this frequency
    let nm : Double
    /// active waypoint when the frequency was set, empty if none
    let fix : String
    let altIn : Double
    let altOut : Double

    /// where the frequency was set: the handoff marker
    let handoff : CLLocationCoordinate2D
    /// entry, the indexed points of the segment, exit
    let path : [CLLocationCoordinate2D]

    /// Altitude band as `freq_cli list` prints it (`{lo:.0f}-{hi:.0f} ft`), here from
    /// the entry and exit altitudes of this one segment
    var altitudeBand : String {
        return String(format: "%.0f-%.0f ft", self.altIn, self.altOut)
    }
}

enum FrequencyTimeline {

    /// Rows for one log, in time order, numbered from 1
    static func rows(index : FrequencyLogIndex) -> [FrequencyTimelineRow] {
        let grouped = self.pointsBySegment(segments: index.segments, points: index.points)
        let reference = index.logDate
        var rv : [FrequencyTimelineRow] = []
        for (i, segment) in index.segments.enumerated() {
            let entry = CLLocationCoordinate2D(latitude: segment.latIn, longitude: segment.lonIn)
            let exit = CLLocationCoordinate2D(latitude: segment.latOut, longitude: segment.lonOut)
            let inner = grouped[i].map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            var elapsed : TimeInterval? = nil
            if let start = segment.start, let reference = reference {
                elapsed = start.timeIntervalSince(reference)
            }
            rv.append(FrequencyTimelineRow(number: i + 1,
                                           freq: segment.freq,
                                           start: segment.start,
                                           elapsed: elapsed,
                                           duration: segment.duration,
                                           nm: segment.nm,
                                           fix: segment.waypointIn,
                                           altIn: segment.altIn,
                                           altOut: segment.altOut,
                                           handoff: entry,
                                           path: [entry] + inner + [exit]))
        }
        return rv
    }

    /// Assign each indexed point to the segment it was sampled from.
    ///
    /// The index does not store a segment number per point, so it is recovered from
    /// the scan's construction: points come segment by segment in time order, carry the
    /// segment's `freq` and `nextFreq`, and their `nmToNext` does not increase within a
    /// segment. A segment can have no points (parked the whole time, below
    /// `minGroundSpeed`), so a point that does not fit the current segment moves to the
    /// next one it matches. Checked exact on every log in TestAssets.
    static func pointsBySegment(segments : [FrequencySegment], points : [FrequencyPoint]) -> [[FrequencyPoint]] {
        var rv : [[FrequencyPoint]] = Array(repeating: [], count: segments.count)
        guard !segments.isEmpty else { return rv }

        func matches(_ j : Int, _ p : FrequencyPoint) -> Bool {
            return segments[j].freq == p.freq && segments[j].nextFreq == p.nextFreq
        }

        var current = 0
        var lastNm : Double? = nil
        for p in points {
            var fits = matches(current, p)
            if fits, let last = lastNm, let nm = p.nmToNext, nm > last {
                // same frequency pair again, but further from its change: a later segment
                fits = false
            }
            if !fits {
                var j = current + 1
                while j < segments.count && !matches(j, p) {
                    j += 1
                }
                guard j < segments.count else { continue }
                current = j
            }
            rv[current].append(p)
            lastNm = p.nmToNext
        }
        return rv
    }

    /// `1:05:12` or `12:34`
    static func format(duration : TimeInterval) -> String {
        let total = Int(duration.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

/// State of the timeline tab for the selected flight. Updated on the main thread.
@Observable
final class FrequencyTimelineViewModel {
    enum State : Equatable {
        /// no flight selected yet
        case idle
        case loading
        case loaded
        /// the index is disabled, or the log could not be parsed
        case unavailable
    }

    private(set) var logFileName : String? = nil
    private(set) var state : State = .idle
    private(set) var rows : [FrequencyTimelineRow] = []
    /// number of the highlighted row, nil for none
    var selected : Int? = nil

    var totalDuration : TimeInterval {
        return self.rows.reduce(0.0) { $0 + $1.duration }
    }

    var selectedRow : FrequencyTimelineRow? {
        guard let selected = self.selected else { return nil }
        return self.rows.first { $0.number == selected }
    }

    func startLoading(logFileName : String) {
        self.logFileName = logFileName
        self.state = .loading
        self.rows = []
        self.selected = nil
    }

    /// Show a loaded index. Ignored if another flight was selected meanwhile.
    func update(index : FrequencyLogIndex) {
        guard index.logFileName == self.logFileName else { return }
        self.rows = FrequencyTimeline.rows(index: index)
        self.selected = nil
        self.state = .loaded
    }

    func unavailable(logFileName : String) {
        guard logFileName == self.logFileName else { return }
        self.rows = []
        self.selected = nil
        self.state = .unavailable
    }

    /// Select a row, or clear the selection if it was already selected
    func toggle(_ number : Int) {
        self.selected = self.selected == number ? nil : number
    }
}
