//
//  FrequencyBingoView.swift
//  FlightLogStats
//
//  Frequency Bingo plan mode screen: route and altitude, the radio (current,
//  previous, next), the ladder table and the map with numbered handoff markers
//  keyed to the table, as on the Frequencies tab. SwiftUI in a
//  UIHostingController, opened only through `FrequencyBingoViewController(launch:)`.
//
//  Design: designs/future/frequency-bingo.md §The page
//

import SwiftUI
import MapKit
import UIKit
import OSLog
import RZFlight

struct FrequencyBingoView: View {
    let model : FrequencyBingoViewModel
    var onDone : () -> Void = {}

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var position : MapCameraPosition = .automatic
    @FocusState private var routeFocused : Bool

    static func color(_ rung : BingoRung) -> Color {
        let palette = FrequencyTimelineView.palette
        return palette[(rung.number - 1) % palette.count]
    }

    var body: some View {
        NavigationStack {
            Group {
                if self.horizontalSizeClass == .compact {
                    VStack(spacing: 8) {
                        self.routeBox
                        self.radio
                        self.map
                            .frame(height: 220)
                        self.table
                    }
                }else{
                    HStack(spacing: 0) {
                        VStack(spacing: 8) {
                            self.routeBox
                            self.radio
                            self.table
                        }
                        .frame(minWidth: 420, idealWidth: 520, maxWidth: 640)
                        Divider()
                        self.map
                    }
                }
            }
            .navigationTitle("Frequency Bingo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { self.onDone() }
                }
            }
        }
        .onChange(of: self.model.routeText) { _, _ in
            // a new route is shown whole; an edit in progress keeps the camera
            if !self.routeFocused {
                self.position = .automatic
            }
        }
    }

    //MARK: - route

    private var routeBox : some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Route: LSGS DJL REM EGTF", text: Binding(get: { self.model.routeText },
                                                                    set: { self.model.routeText = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused(self.$routeFocused)
                    .onSubmit {
                        self.model.submitRoute()
                        self.position = .automatic
                    }
                if !self.model.recent.isEmpty {
                    Menu {
                        ForEach(Array(self.model.recent.enumerated()), id: \.offset) { item in
                            Button(FrequencyBingo.routeString(item.element.route)) {
                                self.routeFocused = false
                                self.model.select(recent: item.element)
                                self.position = .automatic
                            }
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Recent routes")
                }
                Stepper(value: Binding(get: { self.model.cruiseAltitudeFt },
                                       set: { self.model.setCruiseAltitude($0) }),
                        in: FrequencyBingo.altitudeRange,
                        step: FrequencyBingo.altitudeStep) {
                    Text("\(self.model.cruiseAltitudeFt) ft")
                        .font(.body.monospacedDigit())
                }
                .fixedSize()
            }
            if !self.model.unresolved.isEmpty {
                Label("Not found: \(self.model.unresolved.joined(separator: " "))", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    //MARK: - radio

    private var radio : some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 0) {
                Text("CURRENT")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(self.model.radio.current ?? "---.---")
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .foregroundStyle(self.model.radio.current == nil ? Color.secondary : Color.primary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .accessibilityLabel("Current \(self.model.radio.current ?? "not set")")
                Divider()
                HStack {
                    Text("prev")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(self.model.radio.previous ?? "")
                        .font(.body.monospacedDigit())
                    Spacer()
                    Button {
                        self.model.flip()
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .disabled(self.model.radio.previous == nil)
                    .accessibilityLabel("Swap current and previous")
                }
                .padding(.top, 6)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .secondarySystemBackground)))

            VStack(alignment: .leading, spacing: 6) {
                Text("NEXT")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if self.model.next.isEmpty {
                    Text(self.nextPlaceholder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                }
                ForEach(self.model.next, id: \.freq) { guess in
                    Button {
                        self.model.tapNext(guess)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(guess.freq)
                                .font(.title2.monospacedDigit().weight(.semibold))
                            Text(Self.confidence(guess.prob, support: guess.support))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Set as current")
                    if guess.freq != self.model.next.last?.freq {
                        Divider()
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: 220)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .secondarySystemBackground)))
        }
        .padding(.horizontal)
    }

    private var nextPlaceholder : String {
        switch self.model.state {
        case .loading:
            return "Loading frequency index"
        case .unavailable:
            return "Frequency index not available"
        case .ready:
            if self.model.route == nil {
                return "Enter a route"
            }
            return self.model.computing ? "Computing" : "No prediction"
        }
    }

    /// Probability and flights always together: a probability alone overstates
    static func confidence(_ prob : Double, support : Int) -> String {
        return String(format: "%.0f%% · %d flight%@", prob * 100.0, support, support == 1 ? "" : "s")
    }

    //MARK: - table

    private var table : some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    ForEach(self.model.rungs) { rung in
                        BingoRungRow(rung: rung, color: Self.color(rung),
                                     selected: self.model.selected == rung.number - 1,
                                     current: self.model.radio.current,
                                     onAlternate: { self.model.tapAlternate($0, rung: rung.number) })
                            .contentShape(Rectangle())
                            .onTapGesture {
                                self.model.tapRung(rung.number)
                            }
                            .listRowBackground(self.model.selected == rung.number - 1 ? Self.color(rung).opacity(0.15) : Color.clear)
                            .id(rung.number)
                    }
                } header: {
                    self.tableHeader
                } footer: {
                    Text("A watch list, not a clearance: predicted from your own logs (\(self.model.flights) flights), and confidently wrong where they are thin. Keep confidence and flights together. Dashed stretches have no clear winner. Tap a frequency to make it current.")
                }
            }
            .listStyle(.plain)
            .onChange(of: self.model.selected) { _, selected in
                if let selected = selected {
                    withAnimation {
                        proxy.scrollTo(selected + 1, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tableHeader : some View {
        if self.model.computing {
            HStack {
                ProgressView()
                Text("Computing the ladder")
            }
        }else if self.model.rungs.isEmpty {
            Text(self.model.state == .ready && self.model.route != nil ? "No frequency predicted on this route" : "Frequencies along the route")
        }else{
            HStack {
                Text("#").frame(width: 28, alignment: .leading)
                Text("nm").frame(width: 76, alignment: .leading)
                Text("freq")
                Spacer()
                Text("conf · flights · alt")
            }
            .font(.caption.monospacedDigit())
        }
    }

    //MARK: - map

    private var map : some View {
        Map(position: self.$position) {
            ForEach(self.model.rungs) { rung in
                MapPolyline(coordinates: rung.path)
                    .stroke(self.strokeColor(rung),
                            style: StrokeStyle(lineWidth: self.model.selected == rung.number - 1 ? 6 : 3,
                                               lineCap: .round,
                                               dash: rung.rung.unsettled ? [6, 6] : []))
            }
            if self.model.rungs.isEmpty && self.model.routePoints.count >= 2 {
                MapPolyline(coordinates: self.model.routePoints)
                    .stroke(.gray, lineWidth: 2)
            }
            ForEach(self.model.rungs) { rung in
                Annotation(rung.freq, coordinate: rung.handoff, anchor: .center) {
                    FrequencyTimelineMarker(number: rung.number,
                                            color: Self.color(rung),
                                            selected: self.model.selected == rung.number - 1)
                        .onTapGesture {
                            self.model.tapRung(rung.number)
                        }
                }
                .annotationTitles(.hidden)
            }
        }
    }

    private func strokeColor(_ rung : BingoRung) -> Color {
        let color = Self.color(rung)
        if let selected = self.model.selected, selected != rung.number - 1 {
            return color.opacity(0.35)
        }
        return color
    }
}

/// One rung: the number on the map, where it runs, the frequency, confidence with the
/// flights behind it, the altitude sampled there and what else is likely
struct BingoRungRow: View {
    let rung : BingoRung
    let color : Color
    let selected : Bool
    let current : String?
    let onAlternate : (String) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            FrequencyTimelineMarker(number: self.rung.number, color: self.color, selected: false)
                .frame(width: 28, alignment: .leading)
            Text(String(format: "%.0f-%.0f", self.rung.rung.fromNm, self.rung.rung.toNm))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(self.rung.freq)
                    .font(.body.monospacedDigit())
                    .fontWeight(self.rung.freq == self.current ? .bold : .regular)
                if !self.rung.rung.alternates.isEmpty {
                    HStack(spacing: 6) {
                        Text(self.rung.rung.unsettled ? "or" : "also")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(self.rung.rung.alternates, id: \.self) { alternate in
                            Button(alternate) {
                                self.onAlternate(alternate)
                            }
                            .font(.caption.monospacedDigit())
                            .fontWeight(alternate == self.current ? .bold : .regular)
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(FrequencyBingoView.confidence(self.rung.rung.confidence, support: self.rung.rung.support))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(self.rung.rung.unsettled ? Color.orange : Color.primary)
                Text(String(format: "%.0f ft", self.rung.rung.alt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

//MARK: - UIKit shell

/// Hosts the Bingo screen. The only way in: anything with a route builds a
/// `BingoLaunch`, never reaches into the screen's state.
final class FrequencyBingoViewController: UIHostingController<FrequencyBingoView> {
    let bingo : FrequencyBingoViewModel
    private var indexObserver : NSObjectProtocol? = nil

    init(launch : BingoLaunch) {
        let bingo = FrequencyBingoViewModel(launch: launch, store: BingoStore.standard) {
            guard let airports = AppDelegate.knownAirports else { return nil }
            return RoutePointResolver(airports: airports, waypoints: AppDelegate.knownWaypoints)
        }
        self.bingo = bingo
        super.init(rootView: FrequencyBingoView(model: bingo))
        self.rootView = FrequencyBingoView(model: bingo, onDone: { [weak self] in
            self?.dismiss(animated: true)
        })
        self.indexObserver = NotificationCenter.default.addObserver(forName: .frequencyIndexChanged, object: nil, queue: .main) {
            [weak self] _ in
            self?.loadModel()
        }
        self.loadModel()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer = self.indexObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Full screen, a sheet on iPhone
    static func present(launch : BingoLaunch, from presenter : UIViewController) {
        let vc = FrequencyBingoViewController(launch: launch)
        vc.modalPresentationStyle = presenter.traitCollection.horizontalSizeClass == .compact ? .pageSheet : .fullScreen
        presenter.present(vc, animated: true)
    }

    /// The first load reads the whole index, so it runs on worker; later calls are cached
    private func loadModel() {
        guard let index = FlightLogOrganizer.shared.frequencyIndex else {
            self.bingo.update(model: nil)
            return
        }
        AppDelegate.worker.async {
            let model = index.model()
            DispatchQueue.main.async { [weak self] in
                self?.bingo.update(model: model)
            }
        }
    }
}
