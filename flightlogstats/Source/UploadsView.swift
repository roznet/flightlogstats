//
//  UploadsView.swift
//  FlightLogStats
//
//  The upload queue: what is waiting, what failed and why, retry, sign in.
//

import SwiftUI
import UIKit

@MainActor @Observable
final class UploadsModel {
    private(set) var rows : [RecordUploadStore.Row] = []
    private(set) var loaded = false
    private(set) var signInError : String? = nil

    let uploads : Uploads
    var activity : UploadActivity { UploadActivity.shared }

    init(uploads : Uploads = .shared) {
        self.uploads = uploads
    }

    var waiting : [RecordUploadStore.Row] { self.rows.filter { $0.status == .pending } }
    var failed : [RecordUploadStore.Row] { self.rows.filter { $0.status == .failed } }
    var uploadEnabled : Bool { Settings.shared.flystoEnabled }

    func load() async {
        self.rows = await self.uploads.store.overview()
        self.loaded = true
    }

    /// Reload on every upload or failure, while the screen is shown.
    func follow() async {
        await self.load()
        for await _ in NotificationCenter.default.notifications(named: .newFileUploaded) {
            await self.load()
        }
    }

    func retryAll() {
        self.uploads.retryFailed()
    }

    func uploadNextBatch() {
        self.uploads.uploadNextBatch()
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
}

struct UploadsView : View {
    @Bindable var model : UploadsModel
    var dismiss : () -> Void = {}
    @State private var window : UIWindow? = nil

    var body : some View {
        NavigationStack {
            List {
                Section("FlySto") {
                    self.statusRow
                }
                if !self.model.waiting.isEmpty {
                    Section("Waiting") {
                        ForEach(self.model.waiting) { row in
                            self.logRow(row)
                        }
                    }
                }
                if !self.model.failed.isEmpty {
                    Section {
                        ForEach(self.model.failed) { row in
                            self.logRow(row)
                        }
                    } header: {
                        Text("Failed")
                    } footer: {
                        Text("Network errors are retried after 1, 5 and 30 minutes; after that, or when FlySto refused the file, use Retry all.")
                    }
                }
            }
            .navigationTitle("Uploads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: self.dismiss)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Retry all failed", systemImage: "arrow.clockwise") { self.model.retryAll() }
                            .disabled(self.model.failed.isEmpty)
                        Button("Upload next \(Settings.shared.uploadBatchCount) flights", systemImage: "square.and.arrow.up") {
                            self.model.uploadNextBatch()
                        }
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                    .disabled(!self.model.uploadEnabled)
                }
            }
            .task { await self.model.follow() }
        }
        .background(WindowReader(window: self.$window))
    }

    @ViewBuilder private var statusRow : some View {
        let activity = self.model.activity
        if !self.model.uploadEnabled {
            Label("Upload to FlySto is off (Settings)", systemImage: "icloud.slash")
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
        }else if case .uploading(let name, let done, let total) = activity.snapshot.phase {
            VStack(alignment: .leading) {
                Text("Uploading \(done + 1) of \(total)")
                Text(name).font(.footnote).foregroundStyle(.secondary)
                ProgressView(value: Double(done), total: Double(max(total, 1)))
            }
        }else if self.model.loaded && self.model.waiting.isEmpty && self.model.failed.isEmpty {
            Label("Everything queued is uploaded", systemImage: "checkmark.icloud")
                .foregroundStyle(.green)
        }else{
            Label("Idle", systemImage: "pause.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func logRow(_ row : RecordUploadStore.Row) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if let start = row.start {
                    Text(start, format: .dateTime.day().month().year().hour().minute())
                }else{
                    Text(row.name)
                }
                Spacer()
                if let route = row.route {
                    Text(route).foregroundStyle(.secondary)
                }
            }
            if row.status == .failed {
                if let reason = row.reason {
                    Text(reason).font(.footnote).foregroundStyle(.orange)
                }
                if let retry = row.nextRetry {
                    Text("Retry \(retry, format: .relative(presentation: .named))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

final class UploadsViewController : UIHostingController<UploadsView> {
    @MainActor
    init() {
        super.init(rootView: UploadsView(model: UploadsModel()))
        self.rootView.dismiss = { [weak self] in self?.dismiss(animated: true) }
        self.modalPresentationStyle = .formSheet
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
