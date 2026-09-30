//
//  Uploads.swift
//  FlightLogStats
//
//  The app's upload queue: the coordinator over FlySto, persisted in the log records,
//  and what the screens observe.
//

import Foundation
import Network
import OSLog
import UIKit

extension Notification.Name {
    /// a log was uploaded (object: its name)
    static let newFileUploaded : Notification.Name = Notification.Name("Notification.Name.NewFileUploaded")
}

/// Upload progress and service state, for the screens.
@MainActor @Observable
final class UploadActivity {
    static let shared = UploadActivity()

    var snapshot = UploadCoordinator.Snapshot()

    var isUploading : Bool {
        if case .uploading = self.snapshot.phase { return true }
        return false
    }
    var needsSignIn : Bool { self.snapshot.phase == .needsSignIn }
}

final class Uploads : @unchecked Sendable {
    static let shared = Uploads()

    let store : RecordUploadStore
    let coordinator : UploadCoordinator
    private let monitor = NWPathMonitor()

    init(organizer : FlightLogOrganizer = FlightLogOrganizer.shared, service : UploadService = FlyStoService.shared) {
        self.store = RecordUploadStore(organizer: organizer)
        self.coordinator = UploadCoordinator(service: service, store: self.store, report: { snapshot in
            Task { @MainActor in
                UploadActivity.shared.snapshot = snapshot
            }
        })
    }

    /// Once at launch, after the records are loaded: upload what is still queued, and again
    /// whenever the network comes back.
    func start() {
        self.monitor.pathUpdateHandler = { path in
            if path.status == .satisfied {
                self.drain()
            }
        }
        self.monitor.start(queue: DispatchQueue(label: "net.ro-z.flightlogstats.network"))
        self.drain()
    }

    func drain() {
        Task { await self.coordinator.drain() }
    }

    /// New logs from an import: the flights are uploaded if uploads are automatic.
    func uploadAfterImport(_ names : [String]) {
        guard Settings.shared.flystoEnabled, Settings.shared.uploadMethod == .automatic else { return }
        Task {
            let flights = await self.store.flights(among: names)
            if !flights.isEmpty {
                await self.coordinator.enqueue(flights)
            }
        }
    }

    /// The next `Settings.uploadBatchCount` flights not uploaded yet, newest first.
    func uploadNextBatch() {
        Task {
            let names = await self.store.notUploadedFlights(limit: Settings.shared.uploadBatchCount)
            Logger.ui.info("Will upload \(names.count) flights")
            await self.coordinator.enqueue(names)
        }
    }

    /// One log, from its screen.
    /// - Parameter force: upload again even if already uploaded
    func upload(_ name : String, force : Bool = false) {
        Task { await self.coordinator.enqueue([name], force: force) }
    }

    func retryFailed() {
        Task { await self.coordinator.retryFailed() }
    }

    /// Sign in (a user action), then upload what waited for it.
    @MainActor
    func signIn(from window : UIWindow?) async throws {
        let signIn = FlyStoSignIn()
        try await signIn.signIn(from: window)
        await self.coordinator.drain()
    }

    func signOut() {
        Task {
            await FlyStoService.shared.signOut()
            await self.coordinator.drain()
        }
    }
}

/// The queue kept in each log's `FlightFlyStoRecord` (status, attempts, error, next retry),
/// changed on `AppDelegate.worker` like the rest of Core Data.
final class RecordUploadStore : UploadStore, @unchecked Sendable {
    let organizer : FlightLogOrganizer

    init(organizer : FlightLogOrganizer) {
        self.organizer = organizer
    }

    private func onWorker<T>(_ body : @escaping () -> T) async -> T {
        return await withCheckedContinuation { continuation in
            AppDelegate.worker.async {
                continuation.resume(returning: body())
            }
        }
    }

    private func record(_ name : String) -> FlightFlyStoRecord? {
        guard let log = self.organizer[name] else { return nil }
        log.ensureFlyStoStatus()
        return log.flysto_record
    }

    func flights(among names : [String]) async -> [String] {
        return await self.onWorker {
            names.filter { self.organizer[$0]?.isFlight ?? false }
        }
    }

    func notUploadedFlights(limit : Int) async -> [String] {
        return await self.onWorker {
            let list = self.organizer.flightLogFileRecords(request: .flightsOnly) { record in
                (record.recordStatus == .quickParsed || record.recordStatus == .parsed) && record.flystoStatus != .uploaded
            }
            return list.prefix(limit).compactMap { $0.log_file_name }
        }
    }

    func queue(_ names : [String], force : Bool) async -> [String] {
        return await self.onWorker {
            var queued : [String] = []
            for name in names {
                guard let log = self.organizer[name] else { continue }
                if !force && log.flystoStatus == .uploaded { continue }
                guard let record = self.record(name) else { continue }
                record.status = .pending
                record.status_date = Date()
                record.attempts = 0
                record.last_error = nil
                record.next_retry = nil
                queued.append(name)
            }
            self.organizer.saveContext()
            return queued
        }
    }

    func due(now : Date) async -> [UploadJob] {
        return await self.onWorker {
            var jobs : [UploadJob] = []
            for log in self.organizer.flightLogFileRecords(request: .all) {
                guard let name = log.log_file_name, let record = log.flysto_record else { continue }
                let isDue : Bool
                switch record.status {
                case .pending:
                    isDue = true
                case .failed:
                    isDue = record.next_retry.map { $0 <= now } ?? false
                case .ready, .uploaded:
                    isDue = false
                }
                guard isDue else { continue }
                let file = self.organizer.libraryFolder.appendingPathComponent(name)
                // a log still in iCloud waits for its download
                guard FileManager.default.fileExists(atPath: file.path) else { continue }
                jobs.append(UploadJob(name: name, file: file, attempts: Int(record.attempts)))
            }
            return jobs
        }
    }

    func nextRetry() async -> Date? {
        return await self.onWorker {
            self.organizer.flightLogFileRecords(request: .all)
                .compactMap { $0.flysto_record }
                .filter { $0.status == .failed }
                .compactMap { $0.next_retry }
                .min()
        }
    }

    func markUploaded(_ name : String, receipt : UploadReceipt) async {
        await self.onWorker {
            guard let record = self.record(name) else { return }
            record.status = .uploaded
            record.status_date = Date()
            record.last_error = nil
            record.next_retry = nil
            if let response = receipt.response {
                record.upload_response = response
            }
            self.organizer.saveContext()
            NotificationCenter.default.post(name: .newFileUploaded, object: name)
        }
    }

    func markFailed(_ name : String, reason : String, attempts : Int, nextRetry : Date?) async {
        await self.onWorker {
            guard let record = self.record(name) else { return }
            record.status = .failed
            record.status_date = Date()
            record.attempts = Int16(clamping: attempts)
            record.last_error = reason
            record.next_retry = nextRetry
            self.organizer.saveContext()
            NotificationCenter.default.post(name: .newFileUploaded, object: name)
        }
    }

    func failed() async -> [String] {
        return await self.onWorker {
            self.organizer.flightLogFileRecords(request: .all).compactMap { log in
                guard let record = log.flysto_record, record.status == .failed else { return nil }
                return log.log_file_name
            }
        }
    }
}
