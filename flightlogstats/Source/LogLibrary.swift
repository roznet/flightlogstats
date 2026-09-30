//
//  LogLibrary.swift
//  FlightLogStats
//
//  Files side of the library: where the logs live, how they are found on an SD card
//  and copied in. Records stay with `FlightLogOrganizer` on `AppDelegate.worker`.
//

import Foundation
import OSLog

/// One folder holds the logs: the iCloud Drive container `Documents/` when iCloud is
/// available, the app's local `Documents/` otherwise. No two-way copy between them.
struct LogLibrary : Sendable {
    let folder : URL

    init(folder : URL) {
        self.folder = folder
    }

    //MARK: - Import

    /// What the library already has, snapshotted from the organizer before an import.
    struct Known : Sendable {
        var logs : Set<String> = []
        var systemIds : Set<String> = []
        /// guessed date of the newest log, for `.sinceLatestImportedFile`
        var latestGuessedDate : Date? = nil
    }

    enum Selection : Sendable {
        /// every log not in the library yet
        case allMissingFromFolder
        /// only logs at or after the newest one in the library
        case sinceLatestImportedFile
        /// only the picked files, or the logs under a picked folder
        case selectedFile([URL])
        /// only logs at or after the date
        case afterDate(Date)
    }

    struct ImportResult : Sendable, Equatable {
        /// log, rpt and aircraft files found on the source
        var found : Int = 0
        /// new files selected for import
        var candidates : Int = 0
        /// file names now in the library (logs and aircraft files)
        var copied : [String] = []
        var failed : [String] = []
        var cancelled : Bool = false

        var copiedLogs : [String] { self.copied.filter { $0.isFlightLogFile } }
    }

    enum ImportProgress : Sendable, Equatable {
        case discovering
        /// new files found, before copying
        case found(Int)
        case copying(done : Int, total : Int)
        case copied(ImportResult)
        /// records created (quick parse) for these new logs
        case recorded([String])
    }

    /// Above this many new files the user confirms before copying.
    static let largeImportCount = 150

    /// Find, select and copy new files from `picked` (SD card folder, or files) into
    /// the library. Holds the security scope of the picked URLs for the whole import,
    /// copying included.
    ///
    /// - Parameters:
    ///   - largeCount: above this many new files, `confirmLarge` is asked first
    ///   - confirmLarge: asked with the number of new files; false cancels the import
    func importFiles(from picked : [URL],
                     selection : Selection,
                     known : Known,
                     largeCount : Int = Self.largeImportCount,
                     confirmLarge : @Sendable (Int) async -> Bool = { _ in true },
                     progress : @Sendable (ImportProgress) -> Void = { _ in }) async -> ImportResult {
        var result = ImportResult()
        let scoped = picked.filter { $0.startAccessingSecurityScopedResource() }
        defer {
            for url in scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        progress(.discovering)
        let found = Self.discover(in: picked)
        result.found = found.count
        let candidates = self.select(Self.filterMissing(found, known: known, in: self.folder),
                                     selection: selection, known: known)
        result.candidates = candidates.count
        progress(.found(candidates.count))
        Logger.app.info("Import found \(candidates.count) new out of \(found.count)")

        if candidates.count > largeCount {
            if await !confirmLarge(candidates.count) {
                result.cancelled = true
                return result
            }
        }

        for (idx,url) in candidates.enumerated() {
            progress(.copying(done: idx, total: candidates.count))
            if let name = self.copyIn(url) {
                result.copied.append(name)
            }else{
                result.failed.append(url.lastPathComponent)
            }
        }
        progress(.copying(done: candidates.count, total: candidates.count))
        return result
    }

    /// Log, rpt and aircraft files under `urls` (folders are searched deeply), each once.
    /// The caller holds the security scope.
    static func discover(in urls : [URL]) -> [URL] {
        var found : [URL] = []
        var seen : Set<String> = []
        func add(_ url : URL) {
            if url.logFileType != .none && seen.insert(url.standardizedFileURL.path).inserted {
                found.append(url)
            }
        }
        for url in urls {
            var error : NSError? = nil
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) {
                dirurl in
                var isDirectory : ObjCBool = false
                guard FileManager.default.fileExists(atPath: dirurl.path, isDirectory: &isDirectory) else { return }
                if isDirectory.boolValue {
                    // the enumerator is deep: data_log/ is covered without recursing by hand (I4)
                    guard let files = FileManager.default.enumerator(at: dirurl,
                                                                     includingPropertiesForKeys: [.nameKey, .isDirectoryKey],
                                                                     options: [.skipsHiddenFiles]) else {
                        Logger.app.error("Failed to enumerate \(dirurl.path)")
                        return
                    }
                    for case let file as URL in files {
                        add(file)
                    }
                }else{
                    add(dirurl)
                }
            }
            if let error = error {
                Logger.app.error("Failed to coordinate read of \(url.lastPathComponent) \(error.localizedDescription)")
            }
        }
        return found
    }

    /// Drop files the library already has: logs by name (known record or file already in
    /// the folder), aircraft files by system id. rpt files are always kept: they convert
    /// to an aircraft file only if missing.
    static func filterMissing(_ urls : [URL], known : Known, in folder : URL) -> [URL] {
        return urls.filter { url in
            switch url.logFileType {
            case .log:
                let name = url.lastPathComponent
                return !known.logs.contains(name) && !Self.exists(name: name, in: folder)
            case .aircraft:
                if let avionics = AvionicsSystem.from(jsonUrl: url) {
                    return !known.systemIds.contains(avionics.systemId)
                }
                return true
            case .rpt:
                return true
            case .none:
                return false
            }
        }
    }

    func select(_ urls : [URL], selection : Selection, known : Known) -> [URL] {
        return urls.filter { url in
            switch selection {
            case .allMissingFromFolder:
                return true
            case .afterDate(let from):
                if let guessed = url.logFileGuessedDate {
                    return guessed >= from
                }
                return false
            case .selectedFile(let selected):
                return Self.isSelected(url: url, in: selected)
            case .sinceLatestImportedFile:
                guard let latest = known.latestGuessedDate else { return true }
                if let guessed = url.logFileGuessedDate {
                    return guessed >= latest
                }
                return false
            }
        }
    }

    /// True if `url` is one of `selectedUrls` or inside one of them: picking a folder
    /// (the Mac picker default) selects every log found under it.
    static func isSelected(url : URL, in selectedUrls : [URL]) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        for selected in selectedUrls {
            var selectedPath = selected.resolvingSymlinksInPath().standardizedFileURL.path
            if path == selectedPath {
                return true
            }
            if !selectedPath.hasSuffix("/") {
                selectedPath.append("/")
            }
            if path.hasPrefix(selectedPath) {
                return true
            }
        }
        return false
    }

    /// Copy one file into the library, an rpt file becoming `sys_<id>.json`.
    /// - Returns: the name written, nil if nothing was written
    func copyIn(_ url : URL) -> String? {
        if url.logFileType == .rpt {
            guard let avionics = AvionicsSystem(url: url),
                  let json = try? JSONEncoder().encode(avionics) else {
                Logger.app.error("Failed to parse \(url.lastPathComponent)")
                return nil
            }
            let name = avionics.uniqueFileName
            if Self.exists(name: name, in: self.folder) {
                return nil
            }
            return self.write(name: name) { dest in try json.write(to: dest) } ? name : nil
        }
        let name = url.lastPathComponent
        if Self.exists(name: name, in: self.folder) {
            return nil
        }
        return self.write(name: name) { dest in try FileManager.default.copyItem(at: url, to: dest) } ? name : nil
    }

    /// Coordinated write: the folder may be in iCloud Drive.
    private func write(name : String, _ body : (URL) throws -> Void) -> Bool {
        let dest = self.folder.appendingPathComponent(name)
        var coordinationError : NSError? = nil
        var ok = false
        NSFileCoordinator().coordinate(writingItemAt: dest, options: .forReplacing, error: &coordinationError) {
            url in
            do {
                try body(url)
                ok = true
            }catch{
                Logger.app.error("Failed to write \(name) \(error.localizedDescription)")
            }
        }
        if let error = coordinationError {
            Logger.app.error("Failed to coordinate write of \(name) \(error.localizedDescription)")
        }
        return ok
    }

    //MARK: - Files in the folder

    /// True if the file is in `folder`, downloaded or not (an evicted iCloud file is a
    /// hidden `.<name>.icloud` placeholder).
    static func exists(name : String, in folder : URL) -> Bool {
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
            return true
        }
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent(".\(name).icloud").path)
    }

    /// Delete a file from the library (coordinated, so the deletion reaches iCloud Drive).
    func delete(name : String) {
        let url = self.folder.appendingPathComponent(name)
        var coordinationError : NSError? = nil
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) {
            url in
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                    Logger.app.info("Deleted \(name)")
                }
            }catch{
                Logger.app.error("Failed to delete \(name) \(error.localizedDescription)")
            }
        }
        if let error = coordinationError {
            Logger.app.error("Failed to coordinate delete of \(name) \(error.localizedDescription)")
        }
    }

    //MARK: - Moving to one location

    struct Migration : Equatable {
        /// only local: moved into iCloud Drive
        var moved : [String] = []
        /// already in iCloud Drive: the local copy (left by the old two-way sync) is removed
        var removedLocalCopies : [String] = []
        var failed : [String] = []
    }

    /// Move the logs and aircraft files of `local` into `cloud`. A file already in `cloud`
    /// (downloaded or not) has its local copy removed: once logs live in one place, a stale
    /// local copy would bring back a log deleted on another device.
    ///
    /// - Parameter move: moves a file into iCloud Drive, `FileManager.setUbiquitous` in the
    ///   app; tests move within the file system
    static func migrate(local : URL, to cloud : URL,
                        move : (URL, URL) throws -> Void = { try FileManager.default.setUbiquitous(true, itemAt: $0, destinationURL: $1) }) -> Migration {
        var rv = Migration()
        guard local.standardizedFileURL != cloud.standardizedFileURL,
              let names = try? FileManager.default.contentsOfDirectory(atPath: local.path) else { return rv }
        for name in names.sorted() {
            let type = name.logFileType
            guard type == .log || type == .aircraft else { continue }
            let source = local.appendingPathComponent(name)
            do {
                if Self.exists(name: name, in: cloud) {
                    try FileManager.default.removeItem(at: source)
                    rv.removedLocalCopies.append(name)
                }else{
                    try move(source, cloud.appendingPathComponent(name))
                    rv.moved.append(name)
                }
            }catch{
                Logger.sync.error("Failed to move \(name) to iCloud Drive \(error.localizedDescription)")
                rv.failed.append(name)
            }
        }
        if !(rv.moved.isEmpty && rv.removedLocalCopies.isEmpty && rv.failed.isEmpty) {
            Logger.sync.info("Library moved to iCloud Drive: \(rv.moved.count) moved, \(rv.removedLocalCopies.count) local copies removed, \(rv.failed.count) failed")
        }
        return rv
    }

    /// Upload archives the old FlySto request left beside the logs (U7).
    static func removeUploadArchives(in folders : [URL]) {
        for folder in folders {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
            for name in names where name.hasSuffix(".csv.zip") {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
        }
    }
}
