//
//  UploadCoordinator.swift
//  FlightLogStats
//
//  The upload queue: serial, persisted in the records, retried with backoff, paused
//  when the service needs the user to sign in.
//

import Foundation
import OSLog

enum ServiceState : Sendable, Equatable {
    /// switched off in settings
    case disabled
    /// no credential, or it was rejected: only the user can fix it
    case needsSignIn
    case ready
}

/// What the service kept about an upload: FlySto's `{"fileId":...}` answer.
struct UploadReceipt : Sendable, Equatable {
    var response : String? = nil
}

/// Why an upload did not happen, decided by the service, never by its callers.
enum UploadFailure : Error, Sendable, Equatable {
    /// already on the service: counts as uploaded
    case duplicate(UploadReceipt)
    /// credential rejected: the queue pauses until the user signs in
    case auth(String)
    /// network, timeout, server error: retried later
    case transient(String)
    /// the service refuses this file: not retried
    case permanent(String)

    var reason : String {
        switch self {
        case .duplicate: return "Already uploaded"
        case .auth(let message), .transient(let message), .permanent(let message): return message
        }
    }
}

/// A service the logs upload to (FlySto; a fake in tests).
protocol UploadService : Sendable {
    func state() async -> ServiceState
    /// - Throws: `UploadFailure`
    func upload(file : URL) async throws -> UploadReceipt
}

struct UploadJob : Sendable, Equatable {
    let name : String
    let file : URL
    /// failed attempts so far
    let attempts : Int
}

/// Where the queue lives: the per-log upload records.
protocol UploadStore : Sendable {
    /// Queue logs not uploaded yet (or all of them with `force`), resetting their attempts.
    /// - Returns: the names queued
    func queue(_ names : [String], force : Bool) async -> [String]
    /// queued logs, and failed ones whose retry time has come, newest first
    func due(now : Date) async -> [UploadJob]
    /// earliest retry time of a failed log, if any
    func nextRetry() async -> Date?
    func markUploaded(_ name : String, receipt : UploadReceipt) async
    /// - Parameter nextRetry: nil when it is not retried automatically
    func markFailed(_ name : String, reason : String, attempts : Int, nextRetry : Date?) async
    /// logs failed for good, to queue again (Retry all)
    func failed() async -> [String]
}

/// Serial upload queue over one service. Uploads happen after an import, when asked, on
/// launch and when the network comes back; never because a log is displayed.
actor UploadCoordinator {
    enum Phase : Sendable, Equatable {
        case idle
        case uploading(name : String, done : Int, total : Int)
        case needsSignIn
        case disabled
    }

    struct Snapshot : Sendable, Equatable {
        var phase : Phase = .idle
        /// uploaded in the current run
        var uploaded : [String] = []
        /// failed in the current run, with their reason
        var failed : [String:String] = [:]
    }

    /// Wait after the first, second and third transient failure; after that a log waits
    /// for a manual retry.
    static let backoff : [TimeInterval] = [60, 5*60, 30*60]

    let service : UploadService
    let store : UploadStore
    private let report : @Sendable (Snapshot) -> Void
    private let now : @Sendable () -> Date

    private(set) var snapshot = Snapshot() {
        didSet { self.report(self.snapshot) }
    }
    private var draining = false
    private var drainAgain = false
    private var retryTask : Task<Void,Never>? = nil

    init(service : UploadService, store : UploadStore,
         now : @escaping @Sendable () -> Date = { Date() },
         report : @escaping @Sendable (Snapshot) -> Void = { _ in }) {
        self.service = service
        self.store = store
        self.now = now
        self.report = report
    }

    /// Queue logs and start uploading.
    /// - Parameter force: upload again even if already uploaded
    func enqueue(_ names : [String], force : Bool = false) async {
        let queued = await self.store.queue(names, force: force)
        if !queued.isEmpty {
            Logger.net.info("Queued \(queued.count) uploads")
        }
        await self.drain()
    }

    /// Queue again the logs that failed for good.
    func retryFailed() async {
        let failed = await self.store.failed()
        await self.enqueue(failed)
    }

    /// Upload what is due, one at a time. A call while uploading runs again at the end.
    func drain() async {
        guard !self.draining else {
            self.drainAgain = true
            return
        }
        self.draining = true
        defer { self.draining = false }

        repeat {
            self.drainAgain = false
            switch await self.service.state() {
            case .disabled:
                self.snapshot.phase = .disabled
                return
            case .needsSignIn:
                self.snapshot.phase = .needsSignIn
                return
            case .ready:
                break
            }
            let jobs = await self.store.due(now: self.now())
            if jobs.isEmpty {
                break
            }
            self.snapshot.uploaded = []
            self.snapshot.failed = [:]
            for (idx,job) in jobs.enumerated() {
                self.snapshot.phase = .uploading(name: job.name, done: idx, total: jobs.count)
                if await !self.upload(job) {
                    // paused for sign in: the rest stays queued
                    self.snapshot.phase = .needsSignIn
                    return
                }
            }
        } while self.drainAgain

        self.snapshot.phase = .idle
        await self.scheduleRetry()
    }

    /// - Returns: false if the queue must pause for sign in
    private func upload(_ job : UploadJob) async -> Bool {
        do {
            let receipt = try await self.service.upload(file: job.file)
            await self.store.markUploaded(job.name, receipt: receipt)
            self.snapshot.uploaded.append(job.name)
            Logger.net.info("Uploaded \(job.name)")
        }catch let failure as UploadFailure {
            switch failure {
            case .duplicate(let receipt):
                await self.store.markUploaded(job.name, receipt: receipt)
                self.snapshot.uploaded.append(job.name)
                Logger.net.info("Already uploaded \(job.name)")
            case .auth(let message):
                Logger.net.info("Upload paused, sign in needed: \(message)")
                return false
            case .transient(let message):
                let attempts = job.attempts + 1
                let delay = attempts <= Self.backoff.count ? Self.backoff[attempts - 1] : nil
                await self.store.markFailed(job.name, reason: message, attempts: attempts,
                                            nextRetry: delay.map { self.now().addingTimeInterval($0) })
                self.snapshot.failed[job.name] = message
                Logger.net.error("Upload of \(job.name) failed (\(attempts)): \(message)")
            case .permanent(let message):
                await self.store.markFailed(job.name, reason: message, attempts: job.attempts + 1, nextRetry: nil)
                self.snapshot.failed[job.name] = message
                Logger.net.error("Upload of \(job.name) refused: \(message)")
            }
        }catch{
            await self.store.markFailed(job.name, reason: error.localizedDescription, attempts: job.attempts + 1, nextRetry: nil)
            self.snapshot.failed[job.name] = error.localizedDescription
        }
        return true
    }

    /// While the app runs, drain again when the earliest retry is due.
    private func scheduleRetry() async {
        self.retryTask?.cancel()
        self.retryTask = nil
        guard let next = await self.store.nextRetry() else { return }
        let wait = max(next.timeIntervalSince(self.now()), 1)
        self.retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.drain()
        }
    }
}
