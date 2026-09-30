//
//  PostFlightImport.swift
//  FlightLogStats
//
//  The `+` flow in one sheet: SD card → new logs saved to the library → FlySto upload →
//  open the newest flight. Closing the sheet cancels nothing.
//

import SwiftUI
import UIKit
import OSLog

@MainActor @Observable
final class PostFlightImportModel {
    enum Stage : Equatable {
        case discovering
        /// more than `LogLibrary.largeImportCount` new files: waiting for the user
        case confirmLarge(Int)
        case copying(done : Int, total : Int)
        /// copied, creating the records (quick parse)
        case recording(Int)
        case done
        case nothingNew
        case cancelled
    }

    private(set) var stage : Stage = .discovering
    private(set) var result : LogLibrary.ImportResult? = nil
    /// new log records
    private(set) var added : [String] = []
    /// the new logs that are flights, newest first
    private(set) var flights : [String] = []
    /// in iCloud Drive (true) or on this device only
    let savesToICloud : Bool
    private(set) var signInError : String? = nil

    let organizer : FlightLogOrganizer
    let uploads : Uploads
    var activity : UploadActivity { UploadActivity.shared }
    /// open a log in the detail screen
    var openLog : (String) -> Void = { _ in }

    private var confirmation : CheckedContinuation<Bool,Never>? = nil
    private var started = false

    init(organizer : FlightLogOrganizer = .shared, uploads : Uploads = .shared) {
        self.organizer = organizer
        self.uploads = uploads
        self.savesToICloud = organizer.cloudFolder != nil
    }

    var latestFlight : String? { self.flights.first ?? self.added.max() }

    var uploadEnabled : Bool { Settings.shared.flystoEnabled }
    var uploadAutomatic : Bool { Settings.shared.uploadMethod == .automatic }

    func start(picked : [URL], selection : LogLibrary.Selection) {
        guard !self.started else { return }
        self.started = true
        Task {
            let (result, added) = await self.organizer.importLogs(from: picked, selection: selection,
                                                                  confirmLarge: { count in await self.confirmLarge(count) },
                                                                  progress: { step in Task { @MainActor in self.apply(step) } })
            self.result = result
            self.added = added
            if added.isEmpty {
                self.stage = result.cancelled ? .cancelled : .nothingNew
                return
            }
            self.flights = await self.uploads.store.flights(among: added).sorted(by: >)
            self.stage = .done
            self.uploads.uploadAfterImport(added)
        }
    }

    private var isFinished : Bool {
        switch self.stage {
        case .done, .nothingNew, .cancelled: return true
        default: return false
        }
    }
    
    /// Steps arrive in their own tasks: one late after the end is dropped.
    private func apply(_ step : LogLibrary.ImportProgress) {
        guard !self.isFinished else { return }
        switch step {
        case .discovering:
            self.stage = .discovering
        case .found:
            break
        case .copying(let done, let total):
            if case .confirmLarge = self.stage { return }
            self.stage = .copying(done: done, total: total)
        case .copied(let result):
            if !result.copied.isEmpty && !result.cancelled {
                self.stage = .recording(result.copiedLogs.count)
            }
        case .recorded:
            break
        }
    }

    private func confirmLarge(_ count : Int) async -> Bool {
        return await withCheckedContinuation { continuation in
            self.confirmation = continuation
            self.stage = .confirmLarge(count)
        }
    }

    func confirm(_ importAll : Bool) {
        if importAll, case .confirmLarge(let count) = self.stage {
            self.stage = .copying(done: 0, total: count)
        }
        self.confirmation?.resume(returning: importAll)
        self.confirmation = nil
    }

    func signIn(from window : UIWindow?) {
        self.signInError = nil
        Task {
            do {
                try await self.uploads.signIn(from: window)
            }catch{
                self.signInError = error.localizedDescription
            }
        }
    }

    /// A sheet closed while asking goes on as cancelled rather than hanging.
    func dismissed() {
        if self.confirmation != nil {
            self.confirm(false)
        }
    }
}

struct PostFlightImportView : View {
    @Bindable var model : PostFlightImportModel
    var dismiss : () -> Void = {}
    @State private var window : UIWindow? = nil

    var body : some View {
        NavigationStack {
            List {
                Section("SD card") {
                    self.cardRow
                }
                if self.model.stage == .done || self.model.stage.isRecording {
                    Section("Library") {
                        self.libraryRow
                    }
                }
                if self.model.stage == .done && !self.model.flights.isEmpty {
                    Section("FlySto") {
                        self.flystoRow
                    }
                }
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: self.dismiss)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if self.model.stage == .done, let latest = self.model.latestFlight {
                    Button {
                        self.model.openLog(latest)
                        self.dismiss()
                    } label: {
                        Label("Open latest flight", systemImage: "airplane")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding()
                }
            }
        }
        .background(WindowReader(window: self.$window))
    }

    @ViewBuilder private var cardRow : some View {
        switch self.model.stage {
        case .discovering:
            HStack {
                ProgressView()
                Text("Looking for new logs…")
            }
        case .confirmLarge(let count):
            VStack(alignment: .leading, spacing: 12) {
                Label("\(count) new files", systemImage: "externaldrive")
                    .font(.headline)
                Text("This may take a while. Import all of them now, or change the import method in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Import all") { self.model.confirm(true) }
                        .buttonStyle(.borderedProminent)
                    Button("Cancel", role: .cancel) { self.model.confirm(false) }
                        .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)
        case .copying(let done, let total):
            VStack(alignment: .leading) {
                Text("Copying \(min(done + 1, total)) of \(total)")
                ProgressView(value: Double(done), total: Double(max(total, 1)))
            }
        case .recording, .done:
            Label(self.foundText, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .nothingNew:
            Label("No new logs on this card", systemImage: "checkmark.circle")
        case .cancelled:
            Label("Import cancelled", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var foundText : String {
        let logs = self.model.result?.copiedLogs.count ?? self.model.added.count
        return logs == 1 ? "1 new log" : "\(logs) new logs"
    }

    @ViewBuilder private var libraryRow : some View {
        if case .recording = self.model.stage {
            HStack {
                ProgressView()
                Text("Reading the new logs…")
            }
        }else{
            let flights = self.model.flights.count
            Label(self.model.savesToICloud ? "Saved to iCloud Drive" : "Saved on this device",
                  systemImage: self.model.savesToICloud ? "icloud.and.arrow.up" : "internaldrive")
            Text(flights == 1 ? "1 flight" : "\(flights) flights")
                .foregroundStyle(.secondary)
            if let failed = self.model.result?.failed, !failed.isEmpty {
                Label("\(failed.count) could not be copied", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder private var flystoRow : some View {
        let activity = self.model.activity
        if !self.model.uploadEnabled {
            Label("Upload to FlySto is off", systemImage: "icloud.slash")
                .foregroundStyle(.secondary)
        }else if !self.model.uploadAutomatic {
            Text("Automatic upload is off: use More › Upload next flights.")
                .foregroundStyle(.secondary)
        }else if activity.needsSignIn {
            VStack(alignment: .leading, spacing: 8) {
                Label("Sign in to FlySto to upload", systemImage: "person.crop.circle.badge.exclamationmark")
                Button("Sign in") { self.model.signIn(from: self.window) }
                    .buttonStyle(.bordered)
                if let error = self.model.signInError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        }else if case .uploading(_, let done, let total) = activity.snapshot.phase {
            VStack(alignment: .leading) {
                Text("Uploading \(done + 1) of \(total)")
                ProgressView(value: Double(done), total: Double(max(total, 1)))
            }
        }else{
            let uploaded = self.model.flights.filter { activity.snapshot.uploaded.contains($0) }.count
            let failed = self.model.flights.filter { activity.snapshot.failed[$0] != nil }
            if uploaded > 0 {
                Label(uploaded == 1 ? "1 flight uploaded" : "\(uploaded) flights uploaded", systemImage: "checkmark.icloud")
                    .foregroundStyle(.green)
            }
            ForEach(failed, id: \.self) { name in
                VStack(alignment: .leading) {
                    Label("\(name) not uploaded", systemImage: "exclamationmark.icloud")
                        .foregroundStyle(.orange)
                    Text(activity.snapshot.failed[name] ?? "")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if uploaded == 0 && failed.isEmpty {
                HStack {
                    ProgressView()
                    Text("Waiting to upload")
                }
            }
        }
    }
}

private extension PostFlightImportModel.Stage {
    var isRecording : Bool {
        if case .recording = self { return true }
        return false
    }
}

/// The hosting window, for the sign in page to present over.
struct WindowReader : UIViewRepresentable {
    @Binding var window : UIWindow?

    func makeUIView(context: Context) -> UIView {
        let view = WindowReaderView()
        view.onWindow = { window in
            DispatchQueue.main.async { self.window = window }
        }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}

    final class WindowReaderView : UIView {
        var onWindow : (UIWindow?) -> Void = { _ in }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            self.onWindow(self.window)
        }
    }
}

final class PostFlightImportViewController : UIHostingController<PostFlightImportView> {
    let model : PostFlightImportModel

    init(model : PostFlightImportModel) {
        self.model = model
        super.init(rootView: PostFlightImportView(model: model))
        self.rootView.dismiss = { [weak self] in self?.dismiss(animated: true) }
        self.modalPresentationStyle = .formSheet
        if let sheet = self.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if self.isBeingDismissed {
            self.model.dismissed()
        }
    }
}
