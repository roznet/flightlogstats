//
//  TestLogLibrary.swift
//  FlightLogStatsTests
//
//  Import from an SD card layout, selection, one library folder, moving old local logs.
//

import XCTest
@testable import FlightLogStats

final class TestLogLibrary: XCTestCase {

    static let logs = [ TestLogFileSamples.flight2.rawValue + ".csv",
                        TestLogFileSamples.taxiOnly2.rawValue + ".csv",
                        TestLogFileSamples.empty.rawValue + ".csv" ]
    static let rpt = "rpt_220620_134709_N122DR.csv"

    var temp : URL!

    override func setUpWithError() throws {
        self.temp = FileManager.default.temporaryDirectory.appendingPathComponent("TestLogLibrary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: self.temp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: self.temp)
    }

    func folder(_ name : String) throws -> URL {
        let url = self.temp.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// An SD card as the G1000 writes it: logs under data_log/, the rpt file at the root,
    /// and a hidden file that must be skipped.
    func makeSDCard() throws -> URL {
        let bundle = try XCTUnwrap(Bundle(for: type(of: self)).resourceURL)
        let card = try self.folder("sdcard")
        let dataLog = card.appendingPathComponent("data_log")
        try FileManager.default.createDirectory(at: dataLog, withIntermediateDirectories: true)
        for name in Self.logs {
            try FileManager.default.copyItem(at: bundle.appendingPathComponent(name), to: dataLog.appendingPathComponent(name))
        }
        try FileManager.default.copyItem(at: bundle.appendingPathComponent(Self.rpt), to: card.appendingPathComponent(Self.rpt))
        try Data().write(to: dataLog.appendingPathComponent(".log_230101_000000_HIDN.csv"))
        return card
    }

    func names(in folder : URL) -> Set<String> {
        let all = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return Set(all.filter { $0.logFileType != .none })
    }

    /// I4: the deep enumeration covers data_log/, each file is reported once.
    func testDiscoverFindsEachFileOnce() throws {
        let card = try self.makeSDCard()
        let found = LogLibrary.discover(in: [card])
        XCTAssertEqual(found.count, Self.logs.count + 1)
        XCTAssertEqual(Set(found.map { $0.lastPathComponent }), Set(Self.logs + [Self.rpt]))
        // picking the card and its folder reports files once
        XCTAssertEqual(LogLibrary.discover(in: [card, card.appendingPathComponent("data_log")]).count, Self.logs.count + 1)
    }

    func testImportCopiesOnlyNewFiles() async throws {
        let card = try self.makeSDCard()
        let library = LogLibrary(folder: try self.folder("library"))
        var known = LogLibrary.Known()
        known.logs = [Self.logs[0]]

        let result = await library.importFiles(from: [card], selection: .allMissingFromFolder, known: known)
        XCTAssertEqual(result.found, Self.logs.count + 1)
        XCTAssertEqual(Set(result.copiedLogs), Set(Self.logs.dropFirst()))
        // the rpt file becomes the aircraft file
        XCTAssertEqual(result.copied.filter { $0.isAircraftSystemFile }.count, 1)
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertEqual(self.names(in: library.folder), Set(result.copied))

        // again: the files are in the folder, nothing to copy
        let again = await library.importFiles(from: [card], selection: .allMissingFromFolder, known: known)
        XCTAssertTrue(again.copied.isEmpty)
    }

    func testSelection() throws {
        let card = try self.makeSDCard()
        let library = LogLibrary(folder: try self.folder("library"))
        let found = LogLibrary.discover(in: [card])
        let logs = found.filter { $0.isLogFile }

        // I5: a picked folder selects the logs under it, a sibling with a shared prefix does not
        XCTAssertEqual(library.select(found, selection: .selectedFile([card]), known: .init()).count, found.count)
        let sibling = URL(fileURLWithPath: card.path + "x", isDirectory: true)
        XCTAssertTrue(library.select(found, selection: .selectedFile([sibling]), known: .init()).isEmpty)
        let one = try XCTUnwrap(logs.first)
        XCTAssertEqual(library.select(found, selection: .selectedFile([one]), known: .init()), [one])

        // 2022-04-17: the two logs of that day, not the 2022-04-14 and 2022-04-16 ones
        let from = try XCTUnwrap("log_220417_000000_XXXX.csv".logFileGuessedDate)
        let after = library.select(logs, selection: .afterDate(from), known: .init())
        XCTAssertEqual(Set(after.map { $0.lastPathComponent }), [TestLogFileSamples.flight2.rawValue + ".csv"])
        var known = LogLibrary.Known()
        known.latestGuessedDate = from
        XCTAssertEqual(library.select(logs, selection: .sinceLatestImportedFile, known: known), after)
        // an empty library takes everything
        XCTAssertEqual(library.select(logs, selection: .sinceLatestImportedFile, known: .init()).count, logs.count)
    }

    func testLargeImportAsksAndCanBeCancelled() async throws {
        let card = try self.makeSDCard()
        let library = LogLibrary(folder: try self.folder("library"))
        let asked = Asked()
        let result = await library.importFiles(from: [card], selection: .allMissingFromFolder, known: .init(),
                                               largeCount: 2, confirmLarge: { count in
            await asked.set(count)
            return false
        })
        let count = await asked.count
        XCTAssertEqual(count, Self.logs.count + 1)
        XCTAssertTrue(result.cancelled)
        XCTAssertTrue(result.copied.isEmpty)
        XCTAssertTrue(self.names(in: library.folder).isEmpty)
    }

    actor Asked {
        var count : Int? = nil
        func set(_ count : Int) { self.count = count }
    }

    /// One location: local-only logs move to iCloud Drive; a local copy of a file already
    /// there (even evicted) is removed so it cannot bring back a log deleted elsewhere.
    func testMigrationMovesLocalOnlyAndDropsCopies() throws {
        let local = try self.folder("local")
        let cloud = try self.folder("cloud")
        let onlyLocal = "log_220101_000000_AAAA.csv"
        let both = "log_220102_000000_BBBB.csv"
        let evicted = "log_220103_000000_CCCC.csv"
        for name in [onlyLocal, both, evicted, "sys_123.json", "frequencyIndex.db"] {
            try Data(name.utf8).write(to: local.appendingPathComponent(name))
        }
        try Data(both.utf8).write(to: cloud.appendingPathComponent(both))
        try Data().write(to: cloud.appendingPathComponent(".\(evicted).icloud"))

        let migration = LogLibrary.migrate(local: local, to: cloud) { try FileManager.default.moveItem(at: $0, to: $1) }
        XCTAssertEqual(migration.moved, [onlyLocal, "sys_123.json"])
        XCTAssertEqual(migration.removedLocalCopies, [both, evicted])
        XCTAssertTrue(migration.failed.isEmpty)
        XCTAssertTrue(self.names(in: local).isEmpty)
        // other files stay where they are
        XCTAssertTrue(FileManager.default.fileExists(atPath: local.appendingPathComponent("frequencyIndex.db").path))
        XCTAssertEqual(self.names(in: cloud), [onlyLocal, both, "sys_123.json"])
        XCTAssertTrue(LogLibrary.exists(name: evicted, in: cloud))

        // nothing left to do the second time
        XCTAssertEqual(LogLibrary.migrate(local: local, to: cloud) { try FileManager.default.moveItem(at: $0, to: $1) }, .init())
    }

    /// U7: upload archives left beside the logs are removed.
    func testRemoveUploadArchives() throws {
        let folder = try self.folder("archives")
        try Data().write(to: folder.appendingPathComponent("log_220101_000000_AAAA.csv.zip"))
        try Data().write(to: folder.appendingPathComponent("log_220101_000000_AAAA.csv"))
        LogLibrary.removeUploadArchives(in: [folder])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["log_220101_000000_AAAA.csv"])
    }
}
