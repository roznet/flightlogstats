//
//  OwnshipMap.swift
//  FlightLogStats
//
//  Live position on a SwiftUI Map, reusable by any map screen (Frequencies tab
//  now, Bingo live mode next):
//
//  - `LiveLocation`: the GPS feed, one shared instance so the locate toggle is
//    the same on every screen.
//  - `OwnshipMapContent`: the aircraft icon along its track and the one-minute
//    lead vector (`OwnshipVector`), to put inside a `Map { }`.
//  - `.ownshipLocate(_:position:)`: the locate button over the map, which also
//    centres the camera on the first fix and pauses GPS while the map is hidden.
//
//  A host map needs three lines:
//
//      Map(position: $position) {
//          ...
//          if let vector = live.vector { OwnshipMapContent(vector: vector, mapHeading: mapHeading) }
//      }
//      .onMapCameraChange(frequency: .continuous) { mapHeading = $0.camera.heading }
//      .ownshipLocate(live, position: $position)
//

import SwiftUI
import MapKit
import CoreLocation
import OSLog

//MARK: - GPS feed

@MainActor
@Observable
final class LiveLocation {
    static let shared = LiveLocation()

    enum Status : Equatable {
        case off
        /// on, no fix yet
        case waiting
        case tracking
        case denied
        case unavailable
    }

    private(set) var status : Status = .off
    private(set) var location : CLLocation? = nil

    /// the user's toggle; updates also pause while no map shows them
    var isOn : Bool { return self.status != .off }

    var vector : OwnshipVector? {
        guard let location = self.location else { return nil }
        return OwnshipVector(location: location)
    }

    @ObservationIgnored private var updates : Task<Void,Never>? = nil
    @ObservationIgnored private var session : CLServiceSession? = nil
    @ObservationIgnored private var visibleMaps : Int = 0

    func toggle() {
        if self.isOn {
            self.status = .off
            self.location = nil
            self.stopUpdates()
        }else{
            self.status = .waiting
            if self.visibleMaps > 0 {
                self.startUpdates()
            }
        }
    }

    /// a map showing the position appeared or disappeared: GPS runs only while one is visible
    func mapAppeared() {
        self.visibleMaps += 1
        if self.isOn {
            self.startUpdates()
        }
    }

    func mapDisappeared() {
        self.visibleMaps = max(0, self.visibleMaps - 1)
        if self.visibleMaps == 0 {
            self.stopUpdates()
        }
    }

    private func startUpdates() {
        guard self.updates == nil else { return }
        // asks for when-in-use authorisation the first time
        self.session = CLServiceSession(authorization: .whenInUse)
        self.updates = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.airborne) {
                    guard let self = self, !Task.isCancelled else { return }
                    self.received(update)
                }
            }catch{
                Logger.app.error("Location updates failed \(error.localizedDescription)")
            }
        }
    }

    private func stopUpdates() {
        self.updates?.cancel()
        self.updates = nil
        self.session?.invalidate()
        self.session = nil
    }

    private func received(_ update : CLLocationUpdate) {
        guard self.isOn else { return }
        if update.authorizationDenied || update.authorizationDeniedGlobally {
            self.status = .denied
            self.location = nil
        }else if let location = update.location {
            self.status = .tracking
            self.location = location
        }else if update.locationUnavailable {
            self.status = .unavailable
        }
    }
}

//MARK: - map content

/// The aircraft icon pointing along its track, and a line to where it will be
/// after the lead time. Put inside a `Map { }`.
struct OwnshipMapContent : MapContent {
    let vector : OwnshipVector
    /// the map camera heading, so the icon points along the track on a rotated map
    var mapHeading : CLLocationDirection = 0.0

    var body : some MapContent {
        if let lead = self.vector.lead {
            // white casing under the line, so it reads over any segment colour
            MapPolyline(coordinates: [self.vector.coordinate, lead])
                .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            MapPolyline(coordinates: [self.vector.coordinate, lead])
                .stroke(.black, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            Annotation("In 1 min", coordinate: lead, anchor: .center) {
                Circle()
                    .fill(.black)
                    .stroke(.white, lineWidth: 2)
                    .frame(width: 10, height: 10)
                    .accessibilityLabel("Position in \(Int(self.vector.leadTime)) seconds")
            }
            .annotationTitles(.hidden)
        }
        Annotation("Current position", coordinate: self.vector.coordinate, anchor: .center) {
            OwnshipMarker(course: self.vector.course, mapHeading: self.mapHeading)
        }
        .annotationTitles(.hidden)
    }
}

struct OwnshipMarker : View {
    let course : CLLocationDirection?
    let mapHeading : CLLocationDirection

    var body : some View {
        ZStack {
            Circle()
                .fill(.white)
                .shadow(radius: 2)
                .frame(width: 30, height: 30)
            if let course = self.course {
                // the airplane symbol points east: rotate from 90
                Image(systemName: "airplane")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black)
                    .rotationEffect(.degrees(course - 90.0 - self.mapHeading))
            }else{
                Circle()
                    .fill(.black)
                    .frame(width: 12, height: 12)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(self.accessibilityText)
    }

    private var accessibilityText : String {
        guard let course = self.course else { return "Current position" }
        return String(format: "Current position, track %03.0f", course)
    }
}

//MARK: - locate button

struct OwnshipLocateButton : View {
    let live : LiveLocation

    var body : some View {
        Button {
            self.live.toggle()
        } label: {
            Image(systemName: self.systemImage)
                .font(.title3)
                .foregroundStyle(self.live.isOn ? Color.accentColor : Color.primary)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(self.live.isOn ? "Hide current position" : "Show current position")
        .help(self.helpText)
    }

    private var systemImage : String {
        switch self.live.status {
        case .off: return "location"
        case .waiting: return "location.circle"
        case .tracking: return "location.fill"
        case .denied, .unavailable: return "location.slash"
        }
    }

    private var helpText : String {
        switch self.live.status {
        case .off: return "Show current position"
        case .waiting: return "Waiting for position"
        case .tracking: return "Hide current position"
        case .denied: return "Location access denied in Settings"
        case .unavailable: return "Position unavailable"
        }
    }
}

struct OwnshipLocateModifier : ViewModifier {
    let live : LiveLocation
    @Binding var position : MapCameraPosition
    /// the camera moves to the first fix after the toggle, then is left to the user
    @State private var centreOnNextFix = false

    func body(content : Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                OwnshipLocateButton(live: self.live)
                    .padding(10)
            }
            .onChange(of: self.live.isOn) { _, isOn in
                self.centreOnNextFix = isOn
            }
            .onChange(of: self.live.location) { _, location in
                guard self.centreOnNextFix, let location = location else { return }
                self.centreOnNextFix = false
                withAnimation {
                    // ~10 nm across: the one minute vector is 1-3 nm at GA speeds
                    self.position = .region(MKCoordinateRegion(center: location.coordinate,
                                                               latitudinalMeters: 20_000.0,
                                                               longitudinalMeters: 20_000.0))
                }
            }
            .onAppear {
                // back on a map with the toggle on: show where we are now
                self.centreOnNextFix = self.live.isOn
                self.live.mapAppeared()
            }
            .onDisappear {
                self.live.mapDisappeared()
            }
    }
}

extension View {
    /// Locate toggle over a map, centring `position` on the first fix. Draw the
    /// position itself with `OwnshipMapContent` inside the map.
    func ownshipLocate(_ live : LiveLocation, position : Binding<MapCameraPosition>) -> some View {
        return self.modifier(OwnshipLocateModifier(live: live, position: position))
    }
}
