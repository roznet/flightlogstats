//
//  LogFileOrganizer.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 18/04/2022.
//

import Foundation
import RZUtils
import RZUtilsSwift
import UIKit
import CoreData
import OSLog

extension Notification.Name {
    static let localFileListChanged : Notification.Name = Notification.Name("Notification.Name.LocalFileListChanged")
    static let newLocalFilesDiscovered : Notification.Name = Notification.Name("Notification.Name.NewLocalFilesDiscovered")
    static let aircraftListChanged  : Notification.Name = Notification.Name("Notification.Name.AircraftListChanged")
}

/// The library of records. Core Data is used on `AppDelegate.worker` only (the managed
/// objects are still read from main by the screens); files go through `LogLibrary`.
/// Sendable by convention: state changes on `worker`, record maps behind a lock.
class FlightLogOrganizer : @unchecked Sendable {
    public static var shared : FlightLogOrganizer = {
        let organizer = FlightLogOrganizer()
        organizer.frequencyIndex = FrequencyIndexOrganizer(databaseName: "frequencyIndex.db")
        return organizer
    }()

    //MARK: - Flight Log List management
   
    /// flight log records sorted most recent first
    private var flightLogFileRecords : [FlightLogFileRecord] {
        DispatchQueue.synchronized(self) {
            let list = Array(self.managedFlightLogs.values)
            return list.sorted { $0.isNewer(than: $1) }
        }
    }
    
    enum ListRequest {
        case all
        case flightsOnly
        case filtered
    }
    typealias ListFilter = (FlightLogFileRecord) -> Bool
    
    func listFilter(aircrafts : [AircraftRecord]) -> ListFilter {
        typealias SystemId = AircraftRecord.SystemId
        let systemIds : [String] = aircrafts.map { $0.systemId }
        let set = Set(systemIds)
        return { record in
            guard let aircraft = record.aircraftRecord else { return false }
            
            return aircraft.systemId != "" && set.contains(aircraft.systemId)
        }
    }
    
    /// most recent flight log record
    func first(request : ListRequest,  filter : ListFilter? = nil) -> FlightLogFileRecord? {
        return self.flightLogFileRecords(request: request, filter: filter).first
    }
    
    func flightLogFileRecords(request : ListRequest, filter : ListFilter? = nil ) -> [FlightLogFileRecord] {
        let sorted = self.flightLogFileRecords
        
        switch request {
        case .all:
            if let filter = filter {
                return sorted.filter( filter )
            }
            return sorted
        case .filtered:
            if let filter = filter {
                return sorted.filter { info in filter(info) }
            }else{
                return []
            }
        case .flightsOnly:
            if let filter = filter {
                return sorted.filter { info in info.isFlight && filter(info) }
            }else{
                return sorted.filter { info in info.isFlight }
            }
        }
    }

    var count : Int { return DispatchQueue.synchronized(self) { self.managedFlightLogs.count } }
    
    subscript(_ name : String) -> FlightLogFileRecord? {
        return DispatchQueue.synchronized(self) { self.managedFlightLogs[name] }
    }
    
    subscript(log: FlightLogFile) -> FlightLogFileRecord? {
        return self[log.name]
    }
    
    func flight(following info: FlightLogFileRecord) -> FlightLogFileRecord? {
        var rv : FlightLogFileRecord? = nil
        
        var following : FlightLogFileRecord? = nil
        for candidate in self.flightLogFileRecords.reversed() {
            if  info == candidate {
                if let following = following,
                   let end = info.end_airport_icao,
                   let start = following.start_airport_icao,
                   start == end{
                    rv = following
                    break
                }
            }
            following = candidate
        }
        
        return rv
    }
    
    func flight(preceding info: FlightLogFileRecord) -> FlightLogFileRecord? {
        var rv : FlightLogFileRecord? = nil
        
        var following : FlightLogFileRecord? = nil
        for candidate in self.flightLogFileRecords(request: .flightsOnly) {
            if let following = following,
               info == following {
                if
                   let end = candidate.end_airport_icao,
                   let start = following.start_airport_icao,
                   start == end {
                    rv = candidate
                }
                break
            }
            following = candidate
        }
        
        return rv
    }

    //MARK: - Aircraft management
    
    var aircraftCount : Int { return DispatchQueue.synchronized(self) { self.managedAircrafts.count } }
    var aircraftRecords : [AircraftRecord] { return DispatchQueue.synchronized(self) { Array(self.managedAircrafts.values) } }
    /// the aircraft for a system id, if known
    func existingAircraft(systemId : SystemId) -> AircraftRecord? {
        return DispatchQueue.synchronized(self) { self.managedAircrafts[systemId] }
    }
    
    /// the aircraft for a system id, created (worker only) if unknown
    func aircraft(systemId : SystemId, airframeName : String? = nil) -> AircraftRecord {
        if let rv = self.existingAircraft(systemId: systemId) {
            return rv
        }else{
            dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
            let newAircraft = AircraftRecord(context: self.persistentContainer.viewContext)
            newAircraft.uuid = UUID().uuidString
            newAircraft.system_id = systemId
            newAircraft.airframe_name = airframeName
            newAircraft.container = self
            // set default performance
            newAircraft.aircraftPerformance = Settings.shared.aircraftPerformance
            DispatchQueue.synchronized(self) {
                self.managedAircrafts[systemId] = newAircraft
            }
            return newAircraft
        }
    }
    
    var aircraftSystemIds : [SystemId] { return DispatchQueue.synchronized(self) { Array(self.managedAircrafts.keys) } }

    //MARK: - Progress management
    var progress : ProgressReport? = nil

    func ensureProgressReport(callback : @escaping ProgressReport.Callback = { _ in }) {
        if self.progress == nil {
            self.progress = ProgressReport(message: .addingFiles, callback: callback)
        }
    }

    //MARK: - containers

    /// managed aircrafts keyed of system_id
    typealias SystemId = AvionicsSystem.SystemId

    //MARK: - local records management
    /// Mutated on `worker` only, read from anywhere through `synchronized(self)`
    private var managedFlightLogs : [String:FlightLogFileRecord] = [:]
    private var managedAircrafts : [SystemId:AircraftRecord] = [:]
    /// user state per log, keyed by log file name (UserState store)
    private var managedFuelRecords : [String:FlightFuelRecord] = [:]
    private var managedFlyStoRecords : [String:FlightFlyStoRecord] = [:]
    private var hiddenLogs : [String:HiddenLog] = [:]
    
    func fuelRecord(logFileName name : String) -> FlightFuelRecord? {
        return DispatchQueue.synchronized(self) { self.managedFuelRecords[name] }
    }
    func flyStoRecord(logFileName name : String) -> FlightFlyStoRecord? {
        return DispatchQueue.synchronized(self) { self.managedFlyStoRecords[name] }
    }
    /// deleted on some device: import and sync skip it
    func isHidden(logFileName name : String) -> Bool {
        return DispatchQueue.synchronized(self) { self.hiddenLogs[name] != nil }
    }
    var hiddenLogFileNames : Set<String> {
        return DispatchQueue.synchronized(self) { Set(self.hiddenLogs.keys) }
    }
    
    /// Register the fuel record of a log (worker only).
    func register(fuelRecord : FlightFuelRecord, logFileName name : String) {
        fuelRecord.log_file_name = name
        fuelRecord.container = self
        if fuelRecord.uuid == nil {
            fuelRecord.uuid = UUID().uuidString
        }
        DispatchQueue.synchronized(self) { self.managedFuelRecords[name] = fuelRecord }
    }
    
    /// Register the FlySto record of a log (worker only).
    func register(flyStoRecord : FlightFlyStoRecord, logFileName name : String) {
        flyStoRecord.log_file_name = name
        if flyStoRecord.uuid == nil {
            flyStoRecord.uuid = UUID().uuidString
        }
        DispatchQueue.synchronized(self) { self.managedFlyStoRecords[name] = flyStoRecord }
    }
    
    /// Loaded once and shared by every container: each container loading its own copy
    /// makes the entity lookup for the record classes ambiguous (and crash on insert)
    static let managedObjectModel : NSManagedObjectModel = {
        let url = Bundle(for: FlightLogOrganizer.self).url(forResource: "FlightLogModel", withExtension: "momd")!
        return NSManagedObjectModel(contentsOf: url)!
    }()

    /// A container without stores (tests add their own descriptions).
    static func makePersistentContainer() -> NSPersistentContainer {
        return NSPersistentContainer(name: "FlightLogModel", managedObjectModel: Self.managedObjectModel)
    }
    
    /// the app's stores: Derived and UserState (CloudKit) in Application Support
    static func makeLibraryContainer(directory : URL = NSPersistentContainer.defaultDirectoryURL(), cloudKit : Bool = true) -> NSPersistentContainer {
        let needsLegacyCopy = LibraryStore.needsLegacyMigration(directory: directory)
        let container = LibraryStore.makeContainer(model: Self.managedObjectModel, directory: directory, cloudKit: cloudKit)
        if needsLegacyCopy {
            _ = LibraryStore.migrateLegacy(directory: directory, into: container.viewContext)
        }
        return container
    }

    private func createPersistentContainer() -> NSPersistentContainer {
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        let container = Self.makeLibraryContainer()
        self.observeRemoteChanges(of: container)
        return container
    }
    
    lazy var persistentContainer : NSPersistentContainer = {
        return self.createPersistentContainer()
    }()
    
    func saveContext() {
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            }catch{
                let nserror = error as NSError
                Logger.app.error("Failed to save context \(nserror)")
            }
        }
    }
    
    /// Push the UserState schema to the CloudKit Development environment (DEBUG menu).
    func initializeCloudKitSchema() {
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        guard let container = self.persistentContainer as? NSPersistentCloudKitContainer else { return }
        do {
            try container.initializeCloudKitSchema(options: [])
            Logger.app.info("CloudKit schema initialized")
        }catch{
            Logger.app.error("Failed to initialize the CloudKit schema \(error)")
        }
    }
    
    //MARK: - Changes from other devices
    
    private var remoteChangeObserver : NSObjectProtocol? = nil
    /// a reload is queued on worker (worker only)
    private var userStateReloadQueued = false
    
    /// CloudKit imports into the UserState store: reload the user state then.
    private func observeRemoteChanges(of container : NSPersistentContainer) {
        if let observer = self.remoteChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        self.remoteChangeObserver = NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange,
                                                                           object: container.persistentStoreCoordinator,
                                                                           queue: nil) { [weak self] _ in
            AppDelegate.worker.async {
                guard let self = self, !self.userStateReloadQueued else { return }
                self.userStateReloadQueued = true
                // changes come in bursts: one reload for the burst
                AppDelegate.worker.asyncAfter(deadline: .now() + 1.0) {
                    self.userStateReloadQueued = false
                    self.reloadUserState()
                }
            }
        }
    }
    
    /// Fetch the user state again (edits, uploads, deletions from other devices), clean
    /// up duplicates, drop the logs deleted elsewhere, and tell the screens.
    func reloadUserState() {
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        let hiddenBefore = self.hiddenLogFileNames
        self.loadAircraftFromContainer()
        self.loadUserStateFromContainer()
        let newlyHidden = self.hiddenLogFileNames.subtracting(hiddenBefore)
        if !newlyHidden.isEmpty {
            self.removeRecords(names: newlyHidden)
        }
        NotificationCenter.default.post(name: .localFileListChanged, object: self)
        NotificationCenter.default.post(name: .newFileUploaded, object: nil)
    }
    
    func exportCsv() {
        let fields = FlightSummary.Field.allCases
        let fileUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("flights.csv")
        
        var csvString = "file,date,start_ident,end_ident"
        for field in fields {
            csvString += ",\(field.rawValue)"
        }
        csvString += "\n"
        for log in self.flightLogFileRecords {
            if log.isFlight == false {
                continue
            }
            csvString += "\(log.log_file_name ?? ""),\(log.start_time?.ISO8601Format() ?? "")"
            csvString += ",\(log.start_airport_icao ?? "")"
            csvString += ",\(log.end_airport_icao ?? "")"
            for field in fields {
                if let value = log.flightSummary?.measurement(for: field)?.value {
                    csvString += ",\(value)"
                }else {
                    csvString += ","
                }
            }
            csvString += "\n"
        }
        do {
            try csvString.write(to: fileUrl, atomically: true, encoding: .utf8)
            Logger.app.info("Wrote csv to \(fileUrl.path)")
        }catch{
            Logger.app.error("Failed to write csv \(error)")
        }
        
    }

    func loadFromContainer() {
        self.loadAircraftFromContainer()
        self.loadUserStateFromContainer()
        self.loadLogsFromContainer()
    }
    
    /// fetch with current values (another device may have changed them)
    private func fetchFresh<T : NSManagedObject>(_ request : NSFetchRequest<T>) -> [T] {
        request.shouldRefreshRefetchedObjects = true
        do {
            return try self.persistentContainer.viewContext.fetch(request)
        }catch{
            Logger.app.error("Failed to fetch \(request.entityName ?? "") \(error)")
            return []
        }
    }
    
    /// Delete the losing duplicates, save if any.
    private func deleteDuplicates(_ duplicates : [NSManagedObject]) {
        guard !duplicates.isEmpty else { return }
        Logger.app.info("Removing \(duplicates.count) duplicate user records")
        for object in duplicates {
            self.persistentContainer.viewContext.delete(object)
        }
        self.saveContext()
    }
    
    private func loadUserStateFromContainer() {
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        let fuel = LibraryStore.deduplicate(self.fetchFresh(FlightFuelRecord.fetchRequest()),
                                            key: { $0.log_file_name }, isBetter: LibraryStore.isBetter)
        let flysto = LibraryStore.deduplicate(self.fetchFresh(FlightFlyStoRecord.fetchRequest()),
                                              key: { $0.log_file_name }, isBetter: LibraryStore.isBetter)
        let hidden = LibraryStore.deduplicate(self.fetchFresh(HiddenLog.fetchRequest()),
                                              key: { $0.log_file_name }, isBetter: LibraryStore.isBetter)
        for record in fuel.kept.values {
            record.container = self
        }
        DispatchQueue.synchronized(self) {
            self.managedFuelRecords = fuel.kept
            self.managedFlyStoRecords = flysto.kept
            self.hiddenLogs = hidden.kept
        }
        self.deleteDuplicates(fuel.duplicates + flysto.duplicates + hidden.duplicates)
        Logger.app.info("Loaded user state: \(fuel.kept.count) fuel, \(flysto.kept.count) uploads, \(hidden.kept.count) deleted logs")
    }
    
    private func loadLogsFromContainer() {
        let fetchRequest = FlightLogFileRecord.fetchRequest()
        
        do {
            dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
            let fetchedInfo : [FlightLogFileRecord] = try self.persistentContainer.viewContext.fetch(fetchRequest)
            var added = 0
            let existing = self.count
            var needSave = false
            var hidden : [FlightLogFileRecord] = []
            for info in fetchedInfo {
                if let filename = info.log_file_name {
                    if self.isHidden(logFileName: filename) {
                        hidden.append(info)
                        continue
                    }
                    if self[filename] == nil {
                        added += 1
                        info.organizer = self
                        if info.updateForKnownIssues() {
                            needSave = true
                        }
                        DispatchQueue.synchronized(self) {
                            self.managedFlightLogs[filename] = info
                        }
                    }
                }
            }
            // deleted on another device while this one was not running
            for info in hidden {
                self.persistentContainer.viewContext.delete(info)
                needSave = true
            }
            if needSave {
                self.saveContext()
            }
            NotificationCenter.default.post(name: .localFileListChanged, object: self)
            Logger.app.info("Loaded \(fetchedInfo.count) Logs: existing \(existing) added \(added) hidden \(hidden.count)")
            self.updateRecords(count: 1)
        }catch let error{
            Logger.app.error("Failed to query for files \(error)")
        }
    }

    private func loadAircraftFromContainer() {
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        let aircraft = LibraryStore.deduplicate(self.fetchFresh(AircraftRecord.fetchRequest()),
                                                key: { $0.system_id }, isBetter: LibraryStore.isBetter)
        for record in aircraft.kept.values {
            record.container = self
        }
        let existing = self.aircraftCount
        DispatchQueue.synchronized(self) {
            self.managedAircrafts = aircraft.kept
        }
        self.deleteDuplicates(aircraft.duplicates)
        NotificationCenter.default.post(name: .aircraftListChanged, object: self)
        Logger.app.info("Loaded \(aircraft.kept.count) Aircrafts: existing \(existing)")
    }
   
    //MARK: - Parsing records

    /// true while a chain of batches is scheduled on `worker` (worker only)
    private var updateRunning : Bool = false
    /// true while records are being parsed (worker only)
    var isUpdatingRecords : Bool {
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        return self.updateRunning
    }
    /// records to re-parse whatever their state (Rebuild Info), newest first (worker only)
    private var forcedNames : [String] = []
    private var updateTotal : Int = 0
    private var updateDone : Int = 0
    /// files not downloaded from iCloud yet, already asked for (worker only)
    private var downloadRequested : Set<String> = []

    /// Parse the files of records that need it (new, quick parsed, older record version) and
    /// save what they yield, newest first, `count` at a time on `worker` so other work
    /// interleaves. One chain of batches runs at a time; a call while it runs only adds work.
    ///
    /// - Parameters:
    ///   - count: records per batch
    ///   - force: re-parse every record, even those up to date (Rebuild Info)
    func updateRecords(count : Int = 1, force : Bool = false) {
        AppDelegate.worker.async {
            if force {
                self.forcedNames = self.flightLogFileRecords.compactMap { $0.log_file_name }
            }
            guard !self.updateRunning else { return }
            self.updateRunning = true
            self.updateDone = 0
            self.updateTotal = self.forcedNames.count + self.recordsRequiringParsing().count
            if self.updateTotal > 0 {
                Logger.app.info("Will parse \(self.updateTotal) logs")
                self.progress?.update(state: .start, message: .updatingInfo)
            }
            self.runUpdateBatch(count: count)
        }
    }

    /// records whose file needs parsing and is on this device, newest first
    private func recordsRequiringParsing() -> [FlightLogFileRecord] {
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        var rv : [FlightLogFileRecord] = []
        for info in self.flightLogFileRecords where info.requiresParsing {
            guard let name = info.log_file_name else { continue }
            if self.isDownloaded(name: name) {
                rv.append(info)
            }
        }
        return rv.sorted { $1.log_file_name! < $0.log_file_name! }
    }

    /// True if the file is on this device; if it is only in iCloud, ask for it once. The
    /// library watcher parses it when it arrives.
    private func isDownloaded(name : String) -> Bool {
        let url = self.libraryFolder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        if !self.downloadRequested.contains(name) && LogLibrary.exists(name: name, in: self.libraryFolder) {
            self.downloadRequested.insert(name)
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
                Logger.sync.info("Downloading \(name) from iCloud")
            }catch{
                Logger.sync.error("Failed to start download of \(name) \(error.localizedDescription)")
            }
        }
        return false
    }

    private func runUpdateBatch(count : Int) {
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        var batch : [FlightLogFileRecord] = []
        while batch.count < count, let name = self.forcedNames.first {
            self.forcedNames.removeFirst()
            if let info = self[name], self.isDownloaded(name: name) {
                batch.append(info)
            }
        }
        if batch.count < count {
            let names = Set(batch.compactMap { $0.log_file_name })
            let missing = self.recordsRequiringParsing().filter { !names.contains($0.log_file_name!) }
            batch.append(contentsOf: missing.prefix(count - batch.count))
        }

        if batch.isEmpty {
            if self.backfillFrequencyIndex(count: count) > 0 {
                AppDelegate.worker.async { self.runUpdateBatch(count: count) }
                return
            }
            if self.updateDone > 0 {
                Logger.app.info("Parsed \(self.updateDone) logs")
                NotificationCenter.default.post(name: .localFileListChanged, object: nil)
            }
            self.progress?.update(state: .complete)
            self.updateRunning = false
            return
        }

        for info in batch {
            self.parse(record: info)
            self.updateDone += 1
            if self.updateDone % 5 == 0 {
                NotificationCenter.default.post(name: .localFileListChanged, object: nil)
            }
        }
        self.saveContext()
        if self.updateTotal > 0 {
            let percent = Double(min(self.updateDone, self.updateTotal)) / Double(self.updateTotal)
            self.progress?.update(state: .progressing(percent), message: .updatingInfo)
        }
        // next batch after whatever else was queued on worker
        AppDelegate.worker.async { self.runUpdateBatch(count: count) }
    }

    private func parse(record info : FlightLogFileRecord) {
        guard let name = info.log_file_name else {
            info.recordStatus = .error
            return
        }
        if info.flightLog == nil {
            info.flightLog = self.flightLogFile(name: name)
        }
        guard let flightLog = info.flightLog else {
            info.recordStatus = .error
            return
        }
        // the log may be kept parsed by a screen: only clear what this parse loaded
        let logRequiredParsing = flightLog.requiresParsing
        Logger.app.info("Parsing \(name)")
        flightLog.parse()
        do {
            try info.updateFromFlightLog(flightLog: flightLog)
            if let agg = self.aggregatedData {
                agg.insertOrReplace(record: info)
            }
            self.frequencyIndex?.insertOrReplace(flightLog: flightLog)
        }catch{
            info.recordStatus = .error
            Logger.app.error("Failed to update log \(error.localizedDescription)")
        }
        NotificationCenter.default.post(name: .logFileRecordUpdated, object: info)
        if logRequiredParsing {
            flightLog.clear()
        }
    }

    //MARK: - Adding records for files

    /// Create records for files in the library that have none, then parse them.
    /// - Parameter completion: called on `worker` with the names of the new log records
    func addMissingRecordsFromLocal(completion : @escaping ([String]) -> Void = { _ in }){
        AppDelegate.worker.async {
            let urls = LogLibrary.discover(in: [self.libraryFolder])
            self.add(aircrafts: urls)
            let added = self.addMinimum(flightLogFileList: FlightLogFileList(urls: urls))
            self.updateRecords(count: 2)
            completion(added)
        }
    }

    func add(aircrafts: [URL]){
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        var someNew : Int = 0
        var checked : Int = 0
        for url in aircrafts {
            if url.logFileType == .aircraft {
                checked += 1
                if let avionics = AvionicsSystem.from(jsonUrl: url) {
                    if let aircraft = DispatchQueue.synchronized(self, closure: { self.managedAircrafts[ avionics.systemId ] }) {
                        if aircraft.avionicsSystem != avionics {
                            aircraft.avionicsSystem = avionics
                            someNew += 1
                        }
                    }else{
                        Logger.app.info("Registering \(avionics)")
                        let aircraft = AircraftRecord(context: self.persistentContainer.viewContext)
                        aircraft.avionicsSystem = avionics
                        aircraft.aircraftPerformance = Settings.shared.aircraftPerformance
                        DispatchQueue.synchronized(self) {
                            self.managedAircrafts[avionics.systemId] = aircraft
                        }
                        someNew += 1
                    }
                }
            }
        }
        if someNew > 0 {
            Logger.app.info("Found \(someNew) aircrafts to add")
            self.saveContext()
            NotificationCenter.default.post(name: .aircraftListChanged, object: self)
        }else{
            Logger.app.info("No missing aircraft in \(checked) checked")
        }
    }

    /// Add list of flights to the organizer if they are missing.
    /// update the list of record and do a quick parse to save the minimum of details
    /// will not update aggregatedData
    ///
    /// - Parameter flightLogFileList: list of file to add
    /// - Returns: names of the new records (empty if all already there)
    @discardableResult
    func addMinimum(flightLogFileList : FlightLogFileList) -> [String] {
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        var added : [String] = []
        var lastTime = Date()
        let candidates = flightLogFileList.flightLogFiles.filter { $0.name.isFlightLogFile }
        let indexTotal = Double(max(candidates.count, 1))
        self.progress?.update(state: .start, message: .addingFiles)

        for (idx,flightLog) in candidates.enumerated() {
            let filename = flightLog.name
            if let existingRecord = self[filename] {
                // replace if parsed or if flightlog not populated
                if flightLog.isParsed || existingRecord.flightLog == nil {
                    existingRecord.flightLog = flightLog
                }
                continue
            }
            // an iCloud file not downloaded yet gets its record when it arrives
            guard FileManager.default.fileExists(atPath: flightLog.url.path) else { continue }
            // deleted on some device: stays deleted
            guard !self.isHidden(logFileName: filename) else { continue }
            let fileInfo = FlightLogFileRecord(context: self.persistentContainer.viewContext)
            fileInfo.organizer = self
            fileInfo.log_file_name = filename
            fileInfo.flightLog = flightLog
            fileInfo.parseAndUpdate(quick: true)
            Logger.app.info("Added \(fileInfo.recordStatus) record \(filename)")
            DispatchQueue.synchronized(self) {
                self.managedFlightLogs[ filename ] = fileInfo
            }
            added.append(filename)
            if Date().timeIntervalSince(lastTime) > 1.0 {
                lastTime = Date()
                NotificationCenter.default.post(name: .localFileListChanged, object: self)
            }
            self.progress?.update(state: .progressing(Double(idx+1) / indexTotal), message: .addingFiles)
        }
        self.progress?.update(state: .complete, message: .addingFiles)
        if !added.isEmpty {
            Logger.app.info("Added \(added.count) record for new local files")
            self.saveContext()
            NotificationCenter.default.post(name: .localFileListChanged, object: self)
            NotificationCenter.default.post(name: .newLocalFilesDiscovered, object: self)
        }else{
            Logger.app.info("No missing local file in \(flightLogFileList.count) checked")
        }
        return added
    }

    //MARK: - Deleting

    /// Remove the record and its file, and leave a tombstone (`HiddenLog`, synced): the file
    /// is deleted from iCloud Drive, other devices drop the record, and no import brings
    /// the log back, even from an SD card that still has it. Its fuel and upload records
    /// are kept.
    func delete(info : FlightLogFileRecord){
        AppDelegate.worker.async {
            guard let name = info.log_file_name else { return }
            if !self.isHidden(logFileName: name) {
                let hidden = HiddenLog(context: self.persistentContainer.viewContext)
                hidden.log_file_name = name
                hidden.hidden_date = Date()
                hidden.uuid = UUID().uuidString
                DispatchQueue.synchronized(self) {
                    self.hiddenLogs[name] = hidden
                }
            }
            self.library.delete(name: name)
            self.removeRecords(names: [name])
        }
    }
    
    /// Drop the derived records of deleted logs (worker only). Files are left alone: the
    /// device that deleted the log removed it from iCloud Drive.
    private func removeRecords(names : Set<String>) {
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        for name in names {
            guard let info = self[name] else { continue }
            DispatchQueue.synchronized(self) {
                _ = self.managedFlightLogs.removeValue(forKey: name)
            }
            self.frequencyIndex?.delete(logFileName: name)
            info.flightLog = nil
            self.persistentContainer.viewContext.delete(info)
            Logger.app.info("Removed deleted log \(name)")
        }
        self.saveContext()
        NotificationCenter.default.post(name: .localFileListChanged, object: nil)
    }

    private func deletePersistentStores(for container:NSPersistentContainer){
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            if let url = store.url {
                do {
                    Logger.app.info("Deleted store at \(url.path)")
                    try coordinator.destroyPersistentStore(at: url, type: NSPersistentStore.StoreType(rawValue: store.type))
                }catch{
                    Logger.app.error("failed to reset store \(error)")
                }
            }
        }
    }

    func deleteAndResetDatabase() {
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        self.deletePersistentStores(for: self.persistentContainer)
        self.persistentContainer = self.createPersistentContainer()

        DispatchQueue.synchronized(self) {
            self.managedFlightLogs = [:]
            self.managedAircrafts = [:]
            self.managedFuelRecords = [:]
            self.managedFlyStoRecords = [:]
            self.hiddenLogs = [:]
        }
        self.frequencyIndex?.reset()
    }

    func deleteLocalFilesAndDatabase() {
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        self.deleteAndResetDatabase()
        let library = self.library
        var count = 0
        let names = (try? FileManager.default.contentsOfDirectory(atPath: library.folder.path)) ?? []
        for name in names where name.isFlightLogFile {
            library.delete(name: name)
            count += 1
        }
        Logger.app.info("Deleted \(count) out of \(names.count) files")
    }

    //MARK: - Aggregated Data
    /// Maintained full history of aggregatedData.
    /// When records are updated this will be update. Can be nil to disable the aggregation all together
    var aggregatedData : AggregatedDataOrganizer? = nil //AggregatedDataOrganizer(databaseName: "flights.db", table: "aggregatedData")
    
    //MARK: - Frequency Index
    /// COM1 segments and points behind Frequency Bingo, updated as records are parsed.
    /// Nil disables it; only the shared organizer has one, so tests stay hermetic.
    var frequencyIndex : FrequencyIndexOrganizer? = nil
    
    /// Index logs parsed before the frequency index existed, or before it was rebuilt
    /// after a version change: they are not parsed again otherwise, so the incremental
    /// hook in `updateRecords` would never see them.
    /// - Returns: the number of logs processed
    private func backfillFrequencyIndex(count : Int) -> Int {
        guard let index = self.frequencyIndex else { return 0 }
        var todo : [FlightLogFileRecord] = []
        for info in self.flightLogFileRecords {
            if let name = info.log_file_name, info.recordStatus == .parsed, !index.isIndexed(logFileName: name),
               FileManager.default.fileExists(atPath: self.libraryFolder.appendingPathComponent(name).path) {
                todo.append(info)
            }
        }
        guard !todo.isEmpty else { return 0 }
        // most recent first, as for parsing
        todo.sort() { $1.log_file_name! < $0.log_file_name! }
        let batch = todo[..<min(count,todo.count)]
        for info in batch {
            guard let name = info.log_file_name,
                  let flightLog = info.flightLog ?? self.flightLogFile(name: name)
            else { continue }
            let logRequiredParsing = flightLog.requiresParsing
            flightLog.parse()
            // recorded even when it yields nothing, so it is not retried
            index.insertOrReplace(flightLog: flightLog)
            if logRequiredParsing {
                flightLog.clear()
            }
        }
        Logger.app.info("Frequency index backfilled \(batch.count), \(todo.count - batch.count) left")
        return batch.count
    }

    //MARK: - Library folder

    /// the app's own `Documents/`: the library when iCloud is off, and where logs lived
    /// before they moved to iCloud Drive
    var localFolder : URL = { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }()
    /// the iCloud Drive container `Documents/`, set by `openLibrary()` when iCloud is on
    var cloudFolder : URL? = nil
    /// where the logs are: iCloud Drive when available, else local
    var libraryFolder : URL { return self.cloudFolder ?? self.localFolder }
    var library : LogLibrary { return LogLibrary(folder: self.libraryFolder) }

    func flightLogFile(name: String) -> FlightLogFile? {
        return FlightLogFile(url: self.libraryFolder.appendingPathComponent(name))
    }

    /// Resolve the iCloud Drive container and move the logs still only in local
    /// `Documents/` into it. Blocking: `worker` only, before loading the records.
    func openLibrary() {
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        LogLibrary.removeUploadArchives(in: [self.localFolder])
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            Logger.sync.info("iCloud not available, library in local Documents")
            return
        }
        let cloud = container.appendingPathComponent("Documents")
        do {
            try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        }catch{
            Logger.sync.error("Failed to create iCloud Documents \(error.localizedDescription), library stays local")
            return
        }
        self.cloudFolder = cloud
        LogLibrary.removeUploadArchives(in: [cloud])
        let migration = LogLibrary.migrate(local: self.localFolder, to: cloud)
        if !migration.failed.isEmpty {
            // the ones that failed stay local and are tried again next launch; their records
            // point at the library, so they parse once moved
            Logger.sync.error("\(migration.failed.count) files could not move to iCloud Drive")
        }
    }

    //MARK: - Import

    typealias LogSelectionMethod = LogLibrary.Selection
    typealias ImportProgress = LogLibrary.ImportProgress

    /// What the library has, for an import to skip (worker only).
    private func knownSnapshot() -> LogLibrary.Known {
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        var known = LogLibrary.Known()
        DispatchQueue.synchronized(self) {
            known.logs = Set(self.managedFlightLogs.keys)
            known.systemIds = Set(self.managedAircrafts.keys)
            known.hidden = Set(self.hiddenLogs.keys)
        }
        known.latestGuessedDate = self.first(request: .all)?.guessedDate
        return known
    }

    /// The `+` import, off main: find new files under `picked`, copy them into the library
    /// and create their records (quick parse), then parse them fully in the background.
    ///
    /// - Parameters:
    ///   - confirmLarge: asked before copying more than `LogLibrary.largeImportCount` files
    ///   - progress: each step, on an arbitrary thread; ends with `.recorded`, or `.copied`
    ///     if nothing was copied
    /// - Returns: what was copied, and the new log records' names
    @discardableResult
    func importLogs(from picked : [URL],
                    selection : LogSelectionMethod,
                    confirmLarge : @escaping @Sendable (Int) async -> Bool = { _ in true },
                    progress : @escaping @Sendable (ImportProgress) -> Void = { _ in }) async -> (result : LogLibrary.ImportResult, added : [String]) {
        Logger.app.info("Starting import \(String(describing: selection))")
        let (library, known) = await withCheckedContinuation { continuation in
            AppDelegate.worker.async {
                continuation.resume(returning: (self.library, self.knownSnapshot()))
            }
        }
        let result = await library.importFiles(from: picked, selection: selection, known: known,
                                               confirmLarge: confirmLarge, progress: progress)
        progress(.copied(result))
        guard !result.copied.isEmpty else {
            Logger.app.info("Import found no new files")
            return (result, [])
        }
        let added = await withCheckedContinuation { continuation in
            self.addMissingRecordsFromLocal { added in
                continuation.resume(returning: added)
            }
        }
        progress(.recorded(added))
        return (result, added)
    }

    //MARK: - Watching iCloud Drive

    private var libraryQuery : NSMetadataQuery? = nil
    private var libraryObservers : [NSObjectProtocol] = []

    /// Follow the iCloud Drive folder: logs added on another device are downloaded, then
    /// recorded. Started once (main thread), kept running while the app is up.
    func watchLibrary() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard self.libraryQuery == nil else { return }
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        let handler : (Notification) -> Void = { [weak self] _ in self?.libraryQueryChanged() }
        self.libraryObservers = [
            NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main, using: handler),
            NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main, using: handler),
        ]
        if query.start() {
            self.libraryQuery = query
        }else{
            Logger.sync.error("Failed to start iCloud Drive query")
            for observer in self.libraryObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            self.libraryObservers = []
        }
    }

    private func libraryQueryChanged() {
        guard let query = self.libraryQuery else { return }
        query.disableUpdates()
        var downloaded : Set<String> = []
        var toDownload : [URL] = []
        for item in query.results {
            guard let item = item as? NSMetadataItem,
                  let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let name = url.lastPathComponent
            guard name.logFileType == .log || name.logFileType == .aircraft else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status == NSMetadataUbiquitousItemDownloadingStatusCurrent {
                downloaded.insert(name)
            }else{
                toDownload.append(url)
            }
        }
        query.enableUpdates()

        AppDelegate.worker.async {
            for url in toDownload where !self.downloadRequested.contains(url.lastPathComponent) {
                self.downloadRequested.insert(url.lastPathComponent)
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
            if !toDownload.isEmpty {
                Logger.sync.info("\(toDownload.count) files downloading from iCloud")
            }
            let knownLogs = DispatchQueue.synchronized(self) { Set(self.managedFlightLogs.keys).union(self.hiddenLogs.keys) }
            let knownSystemIds = DispatchQueue.synchronized(self) { Set(self.managedAircrafts.keys) }
            let newLogs = downloaded.filter { $0.isFlightLogFile && !knownLogs.contains($0) }
            let newAircraft = downloaded.filter { $0.isAircraftSystemFile && !knownSystemIds.contains(($0 as NSString).deletingPathExtension.replacingOccurrences(of: "sys_", with: "")) }
            let pending = self.recordsRequiringParsing()
            if !newLogs.isEmpty || !newAircraft.isEmpty {
                Logger.sync.info("iCloud Drive has \(newLogs.count) new logs")
                self.addMissingRecordsFromLocal()
            }else if !pending.isEmpty {
                // downloads that finished for records waiting to be parsed
                self.updateRecords(count: 2)
            }
        }
    }
}

extension String {
    enum LogFileType {
        case log
        case aircraft
        case rpt
        case none
    }
    
    var isAircraftSystemFile : Bool { return self.logFileType == .aircraft }
    var isRptFile : Bool { return self.logFileType == .rpt }
    var isFlightLogFile : Bool { self.logFileType == .log }
    
    var logFileType : LogFileType {
        if self.hasSuffix(".csv") {
            if self.hasPrefix("log_") {
                return .log
            } else if self.hasPrefix("rpt_") {
                return .rpt
            }
        }else if self.hasSuffix(".json") {
            if self.hasPrefix("sys_") {
                return .aircraft
            }
        }
        return .none
    }
    var logFileGuessedAirport : String? {
        if self.isFlightLogFile {
            let d = (self as NSString).deletingPathExtension
            if let guess = d.components(separatedBy: "_").last {
                return guess
            }
        }
        return nil
    }

    var logFileGuessedDate : Date? {
        if self.isFlightLogFile || self.isRptFile {
            let d = (self as NSString).deletingPathExtension
            let components = d.components(separatedBy: "_")
            if components.count > 2 {
                let date = "20" + components[1] + components[2]
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMddHHmmss"
                let rv = formatter.date(from: date)
                if rv == nil {
                    //
                }
                return rv
            }
        }
        return nil
    }
}

extension URL {
    typealias LogFileType = String.LogFileType
    var logFileType : LogFileType { return self.lastPathComponent.logFileType }
    var isLogFile : Bool { return self.lastPathComponent.isFlightLogFile }
    var logFileGuessedDate : Date? { return self.lastPathComponent.logFileGuessedDate }
}

