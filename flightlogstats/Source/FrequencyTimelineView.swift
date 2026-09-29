//
//  FrequencyTimelineView.swift
//  FlightLogStats
//
//  Frequencies tab of the log tab bar: the selected flight's COM1 segments as a
//  numbered list, and a map drawing each segment in its own colour with the same
//  numbers at each handoff. SwiftUI in a UIHostingController, inside the UIKit shell
//  (modernisation plan §Phase 6).
//
//  The map draws only from the frequency index, never from FlightData's coordinate
//  frame (known issue C3), so the markers always sit on the drawn line.
//

import SwiftUI
import MapKit
import UIKit
import OSLog

struct FrequencyTimelineView: View {
    let model : FrequencyTimelineViewModel
    var live : LiveLocation = .shared

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var position : MapCameraPosition = .automatic
    @State private var mapHeading : CLLocationDirection = 0.0

    /// cycled along the flight, so adjacent segments always contrast
    static let palette : [Color] = [.blue, .orange, .green, .purple, .red, .teal, .pink, .brown, .indigo, .mint]

    static func color(_ row : FrequencyTimelineRow) -> Color {
        return self.palette[(row.number - 1) % self.palette.count]
    }

    var body: some View {
        Group {
            switch self.model.state {
            case .idle:
                self.message("No flight selected", systemImage: "antenna.radiowaves.left.and.right")
            case .loading:
                ProgressView("Loading frequencies")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable:
                self.message("Frequencies not available for this flight", systemImage: "exclamationmark.triangle")
            case .loaded:
                if self.model.rows.isEmpty {
                    self.message("No COM1 frequency change in this log", systemImage: "antenna.radiowaves.left.and.right.slash")
                }else if self.horizontalSizeClass == .compact {
                    VStack(spacing: 0) {
                        self.map
                        Divider()
                        self.list
                    }
                }else{
                    HStack(spacing: 0) {
                        self.list
                            .frame(minWidth: 320, idealWidth: 380, maxWidth: 460)
                        Divider()
                        self.map
                    }
                }
            }
        }
        .onChange(of: self.model.logFileName) { _, _ in
            self.position = .automatic
        }
        .onChange(of: self.model.selected) { _, _ in
            withAnimation {
                self.position = self.cameraPosition(for: self.model.selectedRow)
            }
        }
    }

    private func message(_ text : String, systemImage : String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    //MARK: - map

    private var map : some View {
        Map(position: self.$position) {
            ForEach(self.model.rows) { row in
                MapPolyline(coordinates: row.path)
                    .stroke(self.strokeColor(row), lineWidth: self.model.selected == row.number ? 6 : 3)
            }
            ForEach(self.model.rows) { row in
                Annotation(row.freq, coordinate: row.handoff, anchor: .center) {
                    FrequencyTimelineMarker(number: row.number,
                                            color: Self.color(row),
                                            selected: self.model.selected == row.number)
                        .onTapGesture {
                            self.model.toggle(row.number)
                        }
                }
                .annotationTitles(.hidden)
            }
            if let vector = self.live.vector {
                OwnshipMapContent(vector: vector, mapHeading: self.mapHeading)
            }
        }
        .onMapCameraChange(frequency: .continuous) { context in
            self.mapHeading = context.camera.heading
        }
        .ownshipLocate(self.live, position: self.$position)
    }

    private func strokeColor(_ row : FrequencyTimelineRow) -> Color {
        let color = Self.color(row)
        if let selected = self.model.selected, selected != row.number {
            return color.opacity(0.35)
        }
        return color
    }

    /// the selected segment with some margin, or the whole flight
    private func cameraPosition(for row : FrequencyTimelineRow?) -> MapCameraPosition {
        guard let row = row, let first = row.path.first else { return .automatic }
        var rect = MKMapRect(origin: MKMapPoint(first), size: MKMapSize(width: 0, height: 0))
        for coordinate in row.path.dropFirst() {
            rect = rect.union(MKMapRect(origin: MKMapPoint(coordinate), size: MKMapSize(width: 0, height: 0)))
        }
        // at least ~2 km across, and a margin of a quarter on each side
        let span = max(rect.size.width, rect.size.height, MKMapPointsPerMeterAtLatitude(first.latitude) * 2000.0)
        rect = rect.insetBy(dx: -(span - rect.size.width) / 2.0 - span / 4.0,
                            dy: -(span - rect.size.height) / 2.0 - span / 4.0)
        return .rect(rect)
    }

    //MARK: - list

    private var list : some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    ForEach(self.model.rows) { row in
                        FrequencyTimelineRowView(row: row, color: Self.color(row),
                                                 selected: self.model.selected == row.number)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                self.model.toggle(row.number)
                            }
                            .listRowBackground(self.model.selected == row.number ? Self.color(row).opacity(0.15) : Color.clear)
                            .id(row.number)
                    }
                } header: {
                    Text("\(self.model.rows.count) frequencies, \(FrequencyTimeline.format(duration: self.model.totalDuration))")
                } footer: {
                    Text("COM1 as recorded by the log, after dropping runs under a minute (radio flicker). The first and last rows are the ground frequencies and are kept even when short. The altitude band is at entry and exit.")
                }
            }
            .listStyle(.plain)
            .onChange(of: self.model.selected) { _, selected in
                if let selected = selected {
                    withAnimation {
                        proxy.scrollTo(selected, anchor: .center)
                    }
                }
            }
        }
    }
}

/// Numbered handoff marker, the same on the map and in the list
struct FrequencyTimelineMarker: View {
    let number : Int
    let color : Color
    let selected : Bool

    var body: some View {
        Text("\(self.number)")
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(.white)
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, self.number > 9 ? 3 : 0)
            .background(Capsule().fill(self.color))
            .overlay(Capsule().stroke(.white, lineWidth: self.selected ? 3 : 1.5))
            .scaleEffect(self.selected ? 1.3 : 1.0)
            .accessibilityLabel("Handoff \(self.number)")
    }
}

struct FrequencyTimelineRowView: View {
    let row : FrequencyTimelineRow
    let color : Color
    let selected : Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            FrequencyTimelineMarker(number: self.row.number, color: self.color, selected: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(self.row.freq)
                    .font(.body.monospacedDigit())
                    .fontWeight(self.selected ? .bold : .semibold)
                Text(self.row.fix.isEmpty ? "no fix" : self.row.fix)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(self.startText)
                    .font(.callout.monospacedDigit())
                Text(FrequencyTimeline.format(duration: self.row.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(self.row.altitudeBand)
                    .font(.callout.monospacedDigit())
                Text(String(format: "%.1f nm", self.row.nm))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 110, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var startText : String {
        guard let start = self.row.start else { return "" }
        return start.formatted(date: .omitted, time: .shortened)
    }
}

//MARK: - UIKit shell

/// Hosts the timeline as a tab of `LogTabBarController`, and loads the selected
/// flight's segments from the frequency index.
class FrequencyTimelineViewController: UIHostingController<FrequencyTimelineView>, ViewModelDelegate {
    let timeline : FrequencyTimelineViewModel

    init() {
        let timeline = FrequencyTimelineViewModel()
        self.timeline = timeline
        super.init(rootView: FrequencyTimelineView(model: timeline))
        self.tabBarItem = UITabBarItem(title: "Frequencies",
                                       image: UIImage(systemName: "antenna.radiowaves.left.and.right"),
                                       selectedImage: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func viewModelDidFinishBuilding(viewModel: FlightLogViewModel) {
    }

    /// Called on main when a flight is selected
    func viewModelHasChanged(viewModel: FlightLogViewModel) {
        let record = viewModel.flightLogFileRecord
        // same flight again: keep what is shown, but retry one that failed to load
        guard let name = record.log_file_name,
              name != self.timeline.logFileName || self.timeline.state == .unavailable else { return }

        self.timeline.startLoading(logFileName: name)
        guard let index = FlightLogOrganizer.shared.frequencyIndex else {
            self.timeline.unavailable(logFileName: name)
            return
        }
        // worker is serial and the selection queued FlightLogViewModel.build() on it
        // first, so the log is parsed by the time this runs
        AppDelegate.worker.async {
            var loaded = index.logIndex(logFileName: name)
            if loaded == nil, let flightLog = record.flightLog {
                Logger.app.info("Indexing frequencies of \(name) for the timeline")
                loaded = index.logIndex(flightLog: flightLog)
            }
            let result = loaded
            DispatchQueue.main.async {
                if let rv = result {
                    self.timeline.update(index: rv)
                }else{
                    self.timeline.unavailable(logFileName: name)
                }
            }
        }
    }
}
