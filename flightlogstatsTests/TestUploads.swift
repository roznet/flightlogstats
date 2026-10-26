//
//  TestUploads.swift
//  FlightLogStatsTests
//
//  Upload queue against a fake service, FlySto error classes, the record-backed store.
//

import XCTest
import OAuthSwift
import CoreData
@testable import FlightLogStats

final class TestUploads: XCTestCase {

    /// Answers from a script, one per upload, and records the order and overlap of calls.
    actor FakeService : UploadService {
        var serviceState : ServiceState = .ready
        var script : [String:[Result<UploadReceipt,UploadFailure>]] = [:]
        var calls : [String] = []
        var running = 0
        var maxRunning = 0

        func setState(_ state : ServiceState) { self.serviceState = state }
        func setScript(_ name : String, _ results : [Result<UploadReceipt,UploadFailure>]) { self.script[name] = results }

        func state() -> ServiceState { self.serviceState }

        func upload(file : URL) async throws -> UploadReceipt {
            let name = file.lastPathComponent
            self.calls.append(name)
            self.running += 1
            self.maxRunning = max(self.maxRunning, self.running)
            // let other work interleave, as a network call would
            try? await Task.sleep(nanoseconds: 1_000_000)
            self.running -= 1
            var results = self.script[name] ?? []
            let result = results.isEmpty ? .success(UploadReceipt(response: "{\"fileId\":\"\(name)\"}")) : results.removeFirst()
            self.script[name] = results
            return try result.get()
        }
    }

    /// The queue in memory: status, attempts, next retry per log.
    actor MemoryStore : UploadStore {
        struct Entry : Equatable {
            var status : RemoteServiceRecord.Status = .ready
            var attempts = 0
            var nextRetry : Date? = nil
            var reason : String? = nil
            var receipt : UploadReceipt? = nil
        }
        var entries : [String:Entry] = [:]

        init(names : [String]) {
            for name in names { self.entries[name] = Entry() }
        }

        func entry(_ name : String) -> Entry? { self.entries[name] }
        func setStatus(_ name : String, _ status : RemoteServiceRecord.Status) { self.entries[name]?.status = status }

        func queue(_ names : [String], force : Bool) -> [String] {
            var rv : [String] = []
            for name in names {
                guard var entry = self.entries[name] else { continue }
                if !force && entry.status == .uploaded { continue }
                entry.status = .pending
                entry.attempts = 0
                entry.nextRetry = nil
                entry.reason = nil
                self.entries[name] = entry
                rv.append(name)
            }
            return rv
        }
        func due(now : Date) -> [UploadJob] {
            return self.entries.keys.sorted(by: >).compactMap { name in
                let entry = self.entries[name]!
                let due = entry.status == .pending || (entry.status == .failed && (entry.nextRetry.map { $0 <= now } ?? false))
                return due ? UploadJob(name: name, file: URL(fileURLWithPath: "/logs/\(name)"), attempts: entry.attempts) : nil
            }
        }
        func nextRetry() -> Date? {
            return self.entries.values.filter { $0.status == .failed }.compactMap { $0.nextRetry }.min()
        }
        func markUploaded(_ name : String, receipt : UploadReceipt) {
            self.entries[name]?.status = .uploaded
            self.entries[name]?.receipt = receipt
            self.entries[name]?.nextRetry = nil
        }
        func markFailed(_ name : String, reason : String, attempts : Int, nextRetry : Date?) {
            self.entries[name]?.status = .failed
            self.entries[name]?.attempts = attempts
            self.entries[name]?.nextRetry = nextRetry
            self.entries[name]?.reason = reason
        }
        func failed() -> [String] {
            return self.entries.filter { $0.value.status == .failed }.map { $0.key }
        }
    }

    final class Clock : @unchecked Sendable {
        private let lock = NSLock()
        private var date = Date(timeIntervalSince1970: 1_700_000_000)
        var now : Date { self.lock.withLock { self.date } }
        func advance(_ seconds : TimeInterval) { self.lock.withLock { self.date = self.date.addingTimeInterval(seconds) } }
    }

    let names = ["log_a.csv", "log_b.csv", "log_c.csv"]

    /// U1: one upload at a time, newest first, and every log ends uploaded.
    func testUploadsOneAtATime() async {
        let service = FakeService()
        let store = MemoryStore(names: self.names)
        let coordinator = UploadCoordinator(service: service, store: store)
        await coordinator.enqueue(self.names)
        let calls = await service.calls
        XCTAssertEqual(calls, self.names.sorted(by: >))
        let maxRunning = await service.maxRunning
        XCTAssertEqual(maxRunning, 1)
        for name in self.names {
            let entry = await store.entry(name)
            XCTAssertEqual(entry?.status, .uploaded)
            XCTAssertEqual(entry?.receipt?.response, "{\"fileId\":\"\(name)\"}")
        }
        let phase = await coordinator.snapshot.phase
        XCTAssertEqual(phase, .idle)

        // already uploaded: queued again only when forced
        await coordinator.enqueue([self.names[0]])
        let again = await service.calls.count
        XCTAssertEqual(again, self.names.count)
        await coordinator.enqueue([self.names[0]], force: true)
        let forced = await service.calls.count
        XCTAssertEqual(forced, self.names.count + 1)
    }

    /// Transient failures back off 1, 5, 30 minutes, then wait for a manual retry.
    func testTransientFailureBacksOff() async {
        let service = FakeService()
        let store = MemoryStore(names: ["log_a.csv"])
        let clock = Clock()
        let coordinator = UploadCoordinator(service: service, store: store, now: { clock.now })
        let offline = Result<UploadReceipt,UploadFailure>.failure(.transient("offline"))
        await service.setScript("log_a.csv", [offline, offline, offline, offline])

        await coordinator.enqueue(["log_a.csv"])
        for (idx,delay) in UploadCoordinator.backoff.enumerated() {
            let entry = await store.entry("log_a.csv")
            XCTAssertEqual(entry?.status, .failed)
            XCTAssertEqual(entry?.attempts, idx + 1)
            XCTAssertEqual(entry?.reason, "offline")
            XCTAssertEqual(entry?.nextRetry, clock.now.addingTimeInterval(delay))
            // not due before its time
            await coordinator.drain()
            let calls = await service.calls.count
            XCTAssertEqual(calls, idx + 1)
            clock.advance(delay)
            await coordinator.drain()
        }
        let last = await store.entry("log_a.csv")
        XCTAssertEqual(last?.attempts, 4)
        XCTAssertNil(last?.nextRetry)

        // Retry all queues it again, and it goes through
        await coordinator.retryFailed()
        let entry = await store.entry("log_a.csv")
        XCTAssertEqual(entry?.status, .uploaded)
    }

    /// An auth failure pauses the queue with the rest still queued; nothing retries until
    /// the service is ready again (the user signed in).
    func testAuthFailurePausesQueue() async {
        let service = FakeService()
        let store = MemoryStore(names: self.names)
        let coordinator = UploadCoordinator(service: service, store: store)
        await service.setScript("log_c.csv", [.failure(.auth("Sign in to FlySto"))])

        await coordinator.enqueue(self.names)
        var phase = await coordinator.snapshot.phase
        XCTAssertEqual(phase, .needsSignIn)
        let calls = await service.calls
        XCTAssertEqual(calls, ["log_c.csv"])
        for name in self.names {
            let entry = await store.entry(name)
            XCTAssertEqual(entry?.status, .pending, name)
            XCTAssertEqual(entry?.attempts, 0, name)
        }

        await service.setState(.needsSignIn)
        await coordinator.drain()
        phase = await coordinator.snapshot.phase
        XCTAssertEqual(phase, .needsSignIn)
        let callsWhilePaused = await service.calls.count
        XCTAssertEqual(callsWhilePaused, 1)

        await service.setState(.ready)
        await coordinator.drain()
        for name in self.names {
            let entry = await store.entry(name)
            XCTAssertEqual(entry?.status, .uploaded, name)
        }
    }

    /// A duplicate counts as uploaded; a refused file fails without retry and does not stop
    /// the others.
    func testDuplicateAndPermanent() async {
        let service = FakeService()
        let store = MemoryStore(names: self.names)
        let coordinator = UploadCoordinator(service: service, store: store)
        await service.setScript("log_c.csv", [.failure(.duplicate(UploadReceipt(response: "{\"fileId\":\"42\"}")))])
        await service.setScript("log_b.csv", [.failure(.permanent("FlySto refused the file (400)"))])
        await coordinator.enqueue(self.names)

        let c = await store.entry("log_c.csv")
        XCTAssertEqual(c?.status, .uploaded)
        XCTAssertEqual(c?.receipt?.response, "{\"fileId\":\"42\"}")
        let b = await store.entry("log_b.csv")
        XCTAssertEqual(b?.status, .failed)
        XCTAssertNil(b?.nextRetry)
        XCTAssertEqual(b?.reason, "FlySto refused the file (400)")
        let a = await store.entry("log_a.csv")
        XCTAssertEqual(a?.status, .uploaded)
        let snapshot = await coordinator.snapshot
        XCTAssertEqual(Set(snapshot.uploaded), ["log_a.csv", "log_c.csv"])
        XCTAssertEqual(snapshot.failed, ["log_b.csv": "FlySto refused the file (400)"])
    }

    func testDisabledServiceUploadsNothing() async {
        let service = FakeService()
        await service.setState(.disabled)
        let store = MemoryStore(names: self.names)
        let coordinator = UploadCoordinator(service: service, store: store)
        await coordinator.enqueue(self.names)
        let calls = await service.calls
        XCTAssertTrue(calls.isEmpty)
        let phase = await coordinator.snapshot.phase
        XCTAssertEqual(phase, .disabled)
    }

    /// U3: a 400 is this file's problem and never signs out; 401/403 and FlySto's 503 refresh
    /// the token once; 409 is a duplicate.
    func testFlyStoClassification() {
        XCTAssertEqual(FlyStoService.classify(status: 401, body: nil), .refreshAndRetry(401))
        XCTAssertEqual(FlyStoService.classify(status: 403, body: nil), .refreshAndRetry(403))
        XCTAssertEqual(FlyStoService.classify(status: 503, body: nil), .refreshAndRetry(503))
        XCTAssertEqual(FlyStoService.classify(status: 409, body: "{\"fileId\":\"7\"}"), .duplicate("{\"fileId\":\"7\"}"))
        XCTAssertEqual(FlyStoService.classify(status: 500, body: nil), .transient("FlySto error 500"))
        XCTAssertEqual(FlyStoService.classify(status: 429, body: nil), .transient("FlySto error 429"))
        guard case .permanent = FlyStoService.classify(status: 400, body: "bad file") else {
            return XCTFail("400 must be permanent")
        }

        // after the refresh: still 401 means sign in, still 503 means try later
        XCTAssertEqual(FlyStoService.Outcome.refreshAndRetry(401).failure(retried: true), .auth("FlySto refused the sign in (401)"))
        XCTAssertEqual(FlyStoService.Outcome.refreshAndRetry(503).failure(retried: true), .transient("FlySto unavailable (503)"))
        XCTAssertEqual(FlyStoService.Outcome.duplicate("{\"fileId\":\"7\"}").failure(retried: false), .duplicate(UploadReceipt(response: "{\"fileId\":\"7\"}")))
        XCTAssertEqual(FlyStoService.Outcome.duplicate("conflict").failure(retried: false), .duplicate(UploadReceipt(response: nil)))

        // network errors are transient, HTTP errors by status
        let offline = OAuthSwiftError.requestError(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet),
                                                   request: URLRequest(url: URL(string: "https://www.flysto.net")!))
        guard case .transient = FlyStoService.classify(offline) else {
            return XCTFail("offline must be transient")
        }
        let conflict = OAuthSwiftError.requestError(error: NSError(domain: OAuthSwiftError.Domain, code: 409, userInfo: ["Response-Body": "{\"fileId\":\"9\"}"]),
                                                    request: URLRequest(url: URL(string: "https://www.flysto.net")!))
        XCTAssertEqual(FlyStoService.classify(conflict), .duplicate("{\"fileId\":\"9\"}"))
        XCTAssertEqual(FlyStoService.classify(.tokenExpired(error: nil)), .refreshAndRetry(401))

        XCTAssertEqual(FlyStoService.fileId(from: "{\"fileId\":\"abc\"}"), "abc")
        XCTAssertNil(FlyStoService.fileId(from: "nope"))
    }

    /// U7: the zip is built in a temporary folder, nothing is left beside the log.
    func testZipLeavesNothingBehind() throws {
        let bundle = try XCTUnwrap(Bundle(for: type(of: self)).resourceURL)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TestZip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appendingPathComponent(TestLogFileSamples.flight2.rawValue + ".csv")
        try FileManager.default.copyItem(at: bundle.appendingPathComponent(log.lastPathComponent), to: log)
        let data = try FlyStoService.zip(log)
        XCTAssertGreaterThan(data.count, 1000)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [log.lastPathComponent])
        XCTAssertThrowsError(try FlyStoService.zip(folder.appendingPathComponent("missing.csv")))
    }

    /// U4: the credential moves from UserDefaults to the Keychain.
    func testKeychainStore() {
        let keychain = KeychainStore(service: "net.ro-z.flightlogstats.test.\(UUID().uuidString)")
        XCTAssertNil(keychain.data(for: "credential"))
        XCTAssertTrue(keychain.set(Data("one".utf8), for: "credential"))
        XCTAssertEqual(keychain.data(for: "credential"), Data("one".utf8))
        XCTAssertTrue(keychain.set(Data("two".utf8), for: "credential"))
        XCTAssertEqual(keychain.data(for: "credential"), Data("two".utf8))
        XCTAssertTrue(keychain.set(nil, for: "credential"))
        XCTAssertNil(keychain.data(for: "credential"))
    }

    func testServiceStateWithoutCredential() async {
        let keychain = KeychainStore(service: "net.ro-z.flightlogstats.test.\(UUID().uuidString)")
        let saved = Settings.shared.flystoCredentials
        Settings.shared.flystoCredentials = nil
        defer { Settings.shared.flystoCredentials = saved }
        let off = FlyStoService(keychain: keychain, isEnabled: { false })
        let offState = await off.state()
        XCTAssertEqual(offState, .disabled)
        let on = FlyStoService(keychain: keychain, isEnabled: { true })
        let onState = await on.state()
        XCTAssertEqual(onState, .needsSignIn)
        do {
            _ = try await on.upload(file: URL(fileURLWithPath: "/nothing.csv"))
            XCTFail("no credential must not upload")
        }catch let failure as UploadFailure {
            // the file is not even read: no sign in page, no request
            XCTAssertEqual(failure, .auth("Sign in to FlySto"))
        }catch{
            XCTFail("\(error)")
        }
    }

    /// The queue persisted in the log records (Core Data, on worker).
    func testRecordStore() async throws {
        let bundle = try XCTUnwrap(Bundle(for: type(of: self)).resourceURL)
        let organizer = FlightLogOrganizer()
        let container = FlightLogOrganizer.makePersistentContainer()
        let description = NSPersistentStoreDescription()
        description.url = URL(fileURLWithPath: "/dev/null")
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in XCTAssertNil(error) }
        organizer.persistentContainer = container
        organizer.localFolder = bundle
        let flight = TestLogFileSamples.flight2.rawValue + ".csv"
        let taxi = TestLogFileSamples.taxiOnly2.rawValue + ".csv"
        _ = AppDelegate.worker.sync {
            organizer.addMinimum(flightLogFileList: FlightLogFileList(urls: [bundle.appendingPathComponent(flight), bundle.appendingPathComponent(taxi)]))
        }
        let store = RecordUploadStore(organizer: organizer)

        let flights = await store.flights(among: [flight, taxi])
        XCTAssertEqual(flights, [flight])
        let queued = await store.queue([flight], force: false)
        XCTAssertEqual(queued, [flight])
        var due = await store.due(now: Date())
        XCTAssertEqual(due.map { $0.name }, [flight])
        XCTAssertEqual(due.first?.file, bundle.appendingPathComponent(flight))

        let retry = Date().addingTimeInterval(60)
        await store.markFailed(flight, reason: "offline", attempts: 1, nextRetry: retry)
        due = await store.due(now: Date())
        XCTAssertTrue(due.isEmpty)
        let next = await store.nextRetry()
        XCTAssertEqual(next, retry)
        due = await store.due(now: retry)
        XCTAssertEqual(due.first?.attempts, 1)

        await store.markUploaded(flight, receipt: UploadReceipt(response: "{\"fileId\":\"1\"}"))
        let record = try XCTUnwrap(organizer[flight])
        AppDelegate.worker.sync {
            XCTAssertEqual(record.flystoStatus, .uploaded)
            XCTAssertNil(record.flystoLastError)
            XCTAssertTrue(record.flystoLogFilesInformationAvailable)
        }
        let requeued = await store.queue([flight], force: false)
        XCTAssertTrue(requeued.isEmpty)
        let notUploaded = await store.notUploadedFlights(limit: 10)
        XCTAssertTrue(notUploaded.isEmpty)
    }

    //MARK: - Dropbox

    /// The Dropbox queue in a JSON file: queued, failed, saved, and the same after a reload.
    func testFileUploadStore() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dropbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in self.names {
            try Data("x".utf8).write(to: folder.appendingPathComponent(name))
        }
        let queueUrl = folder.appendingPathComponent("queue.json")
        let store = FileUploadStore(url: queueUrl, folder: { folder })

        let queued = await store.queue(self.names + ["log_missing.csv"], force: false)
        XCTAssertEqual(queued.count, 4)
        var due = await store.due(now: Date())
        // newest first, and a log not on this device waits
        XCTAssertEqual(due.map { $0.name }, self.names.sorted(by: >))
        XCTAssertEqual(due.first?.file, folder.appendingPathComponent("log_c.csv"))

        let retry = Date().addingTimeInterval(60)
        await store.markFailed("log_c.csv", reason: "offline", attempts: 1, nextRetry: retry)
        await store.markUploaded("log_b.csv", receipt: UploadReceipt(response: "/flights/b.json"))
        due = await store.due(now: Date())
        XCTAssertEqual(due.map { $0.name }, ["log_a.csv"])
        let next = await store.nextRetry()
        XCTAssertEqual(next, retry)

        let reloaded = FileUploadStore(url: queueUrl, folder: { folder })
        let saved = await reloaded.entry("log_b.csv")
        XCTAssertEqual(saved?.status, .uploaded)
        XCTAssertEqual(saved?.receipt, "/flights/b.json")
        let failed = await reloaded.entry("log_c.csv")
        XCTAssertEqual(failed?.lastError, "offline")
        XCTAssertEqual(failed?.attempts, 1)
        let requeued = await reloaded.queue(["log_b.csv"], force: false)
        XCTAssertTrue(requeued.isEmpty)
        let forced = await reloaded.queue(["log_b.csv"], force: true)
        XCTAssertEqual(forced, ["log_b.csv"])
    }

    /// The coordinator drains the file store like the record store.
    func testDropboxQueueThroughCoordinator() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dropbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in self.names {
            try Data("x".utf8).write(to: folder.appendingPathComponent(name))
        }
        let service = FakeService()
        await service.setScript("log_a.csv", [.failure(.permanent("Dropbox refused the file (409)"))])
        let store = FileUploadStore(url: folder.appendingPathComponent("queue.json"), folder: { folder })
        let coordinator = UploadCoordinator(service: service, store: store)
        await coordinator.enqueue(self.names)
        let calls = await service.calls
        XCTAssertEqual(calls, self.names.sorted(by: >))
        let refused = await store.entry("log_a.csv")
        XCTAssertEqual(refused?.status, .failed)
        XCTAssertNil(refused?.nextRetry)
        let saved = await store.entry("log_c.csv")
        XCTAssertEqual(saved?.status, .uploaded)
    }

    func testDropboxClassification() {
        XCTAssertEqual(DropboxService.classify(status: 401, body: nil), .refreshAndRetry)
        XCTAssertEqual(DropboxService.classify(status: 429, body: nil), .transient("Dropbox error 429"))
        XCTAssertEqual(DropboxService.classify(status: 503, body: nil), .transient("Dropbox error 503"))
        if case .permanent(let message) = DropboxService.classify(status: 409, body: "{\"error_summary\": \"path/insufficient_space/\"}") {
            XCTAssertTrue(message.contains("insufficient_space"))
        }else{
            XCTFail("409 is this file's problem")
        }
        if case .permanent = DropboxService.classify(status: 400, body: nil) {}else{
            XCTFail("400 is not retried")
        }
    }

    func testDropboxRequests() throws {
        // the API argument header is ASCII only
        let arg = try DropboxService.apiArg(path: "/flights/2026-10-26_LFAT-EGTF_log_é.json")
        XCTAssertTrue(arg.allSatisfy { $0.isASCII })
        XCTAssertTrue(arg.contains("\\u00e9"))
        XCTAssertTrue(arg.contains("\"mode\":\"overwrite\""))
        XCTAssertTrue(arg.contains("\"path\":\"/flights/"))
        let emoji = try DropboxService.apiArg(path: "/✈️.json")
        XCTAssertTrue(emoji.allSatisfy { $0.isASCII })

        let request = DropboxService.tokenRequest(["grant_type" : "refresh_token", "refresh_token" : "a+b/c=", "client_id" : "key"])
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)
        XCTAssertEqual(body, "client_id=key&grant_type=refresh_token&refresh_token=a%2Bb%2Fc%3D")

        // a refresh answer keeps the refresh token we had
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let refreshed = DropboxService.TokenResponse(access_token: "new", expires_in: 14400, refresh_token: nil)
        XCTAssertEqual(refreshed.credential(refreshToken: "old", now: now),
                       DropboxService.Credential(accessToken: "new", refreshToken: "old", expiresAt: now.addingTimeInterval(14400)))
        XCTAssertNil(refreshed.credential(now: now))
        XCTAssertTrue(DropboxService.Credential(accessToken: "", refreshToken: "", expiresAt: now.addingTimeInterval(30)).isExpired(now: now))
        XCTAssertFalse(DropboxService.Credential(accessToken: "", refreshToken: "", expiresAt: now.addingTimeInterval(3600)).isExpired(now: now))
    }

    /// RFC 7636 appendix B.
    func testPKCEChallenge() {
        XCTAssertEqual(DropboxSignIn.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let verifier = DropboxSignIn.randomString()
        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        XCTAssertLessThanOrEqual(verifier.count, 128)
    }

    func testDropboxStateWithoutCredential() async {
        let keychain = KeychainStore(service: "net.ro-z.flightlogstats.test.\(UUID().uuidString)")
        let off = DropboxService(keychain: keychain, isEnabled: { false }, content: { _ in ("x.json", Data()) })
        let offState = await off.state()
        XCTAssertEqual(offState, .disabled)
        let on = DropboxService(keychain: keychain, isEnabled: { true }, content: { _ in
            XCTFail("no credential must not build the summary")
            return ("x.json", Data())
        })
        let onState = await on.state()
        XCTAssertEqual(onState, .needsSignIn)
        do {
            _ = try await on.upload(file: URL(fileURLWithPath: "/nothing.csv"))
            XCTFail("no credential must not upload")
        }catch let failure as UploadFailure {
            XCTAssertEqual(failure, .auth("Sign in to Dropbox"))
        }catch{
            XCTFail("\(error)")
        }
    }

    /// The summary of a real flight: times in order, durations, JSON round trip, file name.
    func testFlightSummaryExport() throws {
        let url = try XCTUnwrap(TestLogFileSamples.flight2.url)
        let log = try XCTUnwrap(FlightLogFile(url: url))
        log.parse()
        let flight = try XCTUnwrap(log.flightSummary)
        let export = FlightSummaryExport(logFile: log.name, summary: flight,
                                         aircraft: .init(registration: "N123AB", airframe: "SR22T", systemId: "1"),
                                         departureIcao: "LFQA", arrivalIcao: "LFAQ")
        let times = export.timesUtc
        let ordered = [times.logStart, times.engineOn, times.blockOff, times.takeoff,
                       times.landing, times.blockOn, times.engineOff, times.logEnd].compactMap { $0 }
        XCTAssertEqual(ordered.count, 8)
        XCTAssertEqual(ordered, ordered.sorted())
        let block = try XCTUnwrap(export.durations.blockMinutes)
        let airborne = try XCTUnwrap(export.durations.airborneMinutes)
        XCTAssertGreaterThan(airborne, 0)
        XCTAssertGreaterThanOrEqual(block, airborne)
        XCTAssertGreaterThan(export.fuelLiters.usedTotalizer, export.fuelUsGallons.usedTotalizer)
        XCTAssertEqual(export.version, FlightSummaryExport.formatVersion)

        let data = try export.json()
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"block_off\""))
        XCTAssertTrue(json.contains("\"fuel_us_gallons\""))
        XCTAssertEqual(try FlightSummaryExport.decoder.decode(FlightSummaryExport.self, from: data), export)

        XCTAssertTrue(export.fileName.hasPrefix(try XCTUnwrap(export.date)))
        XCTAssertTrue(export.fileName.hasSuffix("_log_220417_125002_LFQA.json"))
        XCTAssertTrue(export.summary.contains("N123AB"))
        XCTAssertTrue(export.clipboardText().hasPrefix(export.summary))
    }
}
