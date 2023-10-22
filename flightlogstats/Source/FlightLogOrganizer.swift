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
    static let noFileDiscovered : Notification.Name = Notification.Name("Notification.Name.NoFileDiscovered")
}

class FlightLogOrganizer {
    enum OrganizerError : Error {
        case failedToReadFolder
    }
    public static var shared = FlightLogOrganizer()
    public static let scheduler = DispatchQueue(label: "net.ro-z.flightlogstats.scheduler")
    
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

    var count : Int { return managedFlightLogs.count }
    
    subscript(_ name : String) -> FlightLogFileRecord? {
        return self.managedFlightLogs[name]
    }
    
    subscript(log: FlightLogFile) -> FlightLogFileRecord? {
        return self.managedFlightLogs[log.name]
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
    
    var aircraftCount : Int { return self.managedAircrafts.count }
    var aircraftRecords : [AircraftRecord] { return Array(self.managedAircrafts.values) }
    func aircraft(systemId : SystemId, airframeName : String? = nil) -> AircraftRecord {
        if let rv = self.managedAircrafts[systemId] {
            return rv
        }else{
            dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
            let newAircraft = AircraftRecord(context: self.persistentContainer.viewContext)
            newAircraft.system_id = systemId
            newAircraft.airframe_name = airframeName
            // set default performance
            newAircraft.aircraftPerformance = Settings.shared.aircraftPerformance
            self.managedAircrafts[systemId] = newAircraft
            return newAircraft
        }
    }
    
    var aircraftSystemIds : [SystemId] { return Array(self.managedAircrafts.keys) }
    
    //MARK: - Progress management
    var progress : ProgressReport? = nil

    func ensureProgressReport(callback : @escaping ProgressReport.Callback = { _ in }) {
        if self.progress == nil {
            self.progress = ProgressReport(message: .addingFiles, callback: callback)
        }
    }
    
    //MARK: - containers
    
    enum UpdateState {
        case ready
        case complete
        case updatingInfoFromData
    }
    
    /// managed logs keyed of log_file_name
    private var currentState : UpdateState = .complete
    private var missingCount : Int = 0
    private var doneCount : Int = 0
    private let queue = OperationQueue()

    /// managed aircrafts keyed of system_id
    typealias SystemId = AvionicsSystem.SystemId
    
    //MARK: - local records management
    private var managedFlightLogs : [String:FlightLogFileRecord] = [:]
    private var managedAircrafts : [SystemId:AircraftRecord] = [:]
    
    private func createPersistentContainer() -> NSPersistentContainer {
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        let container = NSPersistentContainer(name: "FlightLogModel")
        container.loadPersistentStores() {
            (storeDescription,error) in
            if let error = error {
                Logger.app.error("Failed to load \(error.localizedDescription)")
            }else{
                let path = storeDescription.url?.path ?? ""
                Logger.app.info("Loaded store \(storeDescription.type) \(path.truncated(limit: 64))")
                container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                self.checkForUpdates()
            }
        }
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
    
    func checkForUpdates() {
        Settings.shared.databaseVersion = 1
    }
    
    func loadFromContainer() {
        self.loadAircraftFromContainer()
        self.loadAircraftFromCloudContainer()
        self.loadLogsFromContainer()
    }
    
    private func loadLogsFromContainer() {
        let fetchRequest = FlightLogFileRecord.fetchRequest()
        
        do {
            dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
            let fetchedInfo : [FlightLogFileRecord] = try self.persistentContainer.viewContext.fetch(fetchRequest)
            var added = 0
            let existing = self.managedFlightLogs.count
            var needSave = false
            for info in fetchedInfo {
                if let filename = info.log_file_name {
                    if self.managedFlightLogs[filename] == nil {
                        added += 1
                        info.organizer = self
                        if info.updateForKnownIssues() {
                            needSave = true
                        }
                        self.managedFlightLogs[filename] = info
                    }
                }
            }
            NotificationCenter.default.post(name: .localFileListChanged, object: self)
            if needSave {
                Logger.app.info("Found corrections to be done")
            }
            Logger.app.info("Loaded \(fetchedInfo.count) Logs: existing \(existing) added \(added) ")
            self.updateRecords(count: 1)
        }catch{
            Logger.app.error("Failed to query for files")
        }
    }

    private func loadAircraftFromContainer() {
        let fetchRequest = AircraftRecord.fetchRequest()
        
        do {
            dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
            let fetchAircrafts : [AircraftRecord] = try self.persistentContainer.viewContext.fetch(fetchRequest)
            var added = 0
            let existing = self.managedAircrafts.count
            for aircraft in fetchAircrafts {
                if let systemId = aircraft.system_id {
                    added += 1
                    aircraft.container = self
                    self.managedAircrafts[systemId] = aircraft
                }
            }
            NotificationCenter.default.post(name: .aircraftListChanged, object: self)
            Logger.app.info("Loaded \(fetchAircrafts.count) Aircrafts: existing \(existing) added \(added)")
        }catch{
            Logger.app.error("Failed to query for aircrafts")
        }
    }
   
    /// update record by parsing the log file and extracting summary information from the file
    /// Will save the summary to the database.
    /// If aggregatedData is not nil, will also update the aggregated data
    ///
    /// - Parameters:
    ///   - count: maximum number of record to process
    ///   - force: if true will parse and update logs for record even if already parsed
    func updateRecords(count : Int = 1, force : Bool = false) {
        guard currentState != .updatingInfoFromData else { return }
        let firstMissingCheck : Bool = (currentState == .complete)
        currentState = .updatingInfoFromData
        AppDelegate.worker.async {
            var missing : [FlightLogFileRecord] = []
            for (_,info) in self.managedFlightLogs {
                if force || info.requiresParsing{
                    if firstMissingCheck, let log_file_name = info.log_file_name {
                        if !force {
                            Logger.app.info("Will update info for \(log_file_name) status=\(info.recordStatus)")
                        }
                    }
                    missing.append(info)
                }
            }
            if !missing.isEmpty {
                if firstMissingCheck {
                    self.missingCount = missing.count
                    self.doneCount = 0
                    self.progress?.update(state: .start, message: .updatingInfo)
                    
                }
                if missing.count > self.missingCount {
                    self.missingCount = missing.count
                }
                
                let reportParsingProgress : Bool = (force && count < 3 ) || self.missingCount < 3
                var done : [String] = []
                // do more recent first
                missing.sort() { $1.log_file_name! < $0.log_file_name! }
                for info in missing[..<min(count,missing.count)] {
                    guard let log_file_name = info.log_file_name
                    else {
                        info.recordStatus = .error
                        continue
                    }
                    
                    if info.flightLog == nil {
                        info.flightLog = self.flightLogFile(name: log_file_name)
                    }
                    
                    if let flightLog = info.flightLog {
                        // if not already parsed, we will clear it
                        let logRequiredParsing = flightLog.requiresParsing
                        // only report parsing progress if few missing, if many, just report overall progress
                        // Note info may require parsing due to version change, while log may not if already
                        // parsed
                        if info.requiresParsing || force{
                            Logger.app.info("Parsing \(log_file_name)")
                            
                            flightLog.parse(progress: reportParsingProgress ? self.progress : nil)
                            do {
                                try info.updateFromFlightLog(flightLog: flightLog)
                                if let agg = self.aggregatedData {
                                    agg.insertOrReplace(record: info)
                                }
                            }catch{
                                info.recordStatus = .error
                                Logger.app.error("Failed to update log \(error.localizedDescription)")
                            }
                            
                            NotificationCenter.default.post(name: .logFileRecordUpdated, object: info)
                            //restore the state
                            if logRequiredParsing {
                                flightLog.clear()
                            }
                            done.append(log_file_name)
                        }else{
                            Logger.app.error("Skipping \(log_file_name) status=\(flightLog.logType)")
                        }
                    }else{
                        info.recordStatus = .error
                    }
                    self.doneCount += 1
                    if !reportParsingProgress {
                        let percent = (Double(min(self.doneCount,self.missingCount))/Double(self.missingCount))
                        self.progress?.update(state: .progressing(percent), message: .updatingInfo)
                    }
                    if self.doneCount % 5 == 0 {
                        NotificationCenter.default.post(name: .localFileListChanged, object: nil)
                    }
                }
                let firstName = done.last ?? ""
                Logger.app.info("Updated \(self.doneCount)/\(self.missingCount) info last=\(firstName)")
                self.saveContext()
                // need to switch state before starting next
                if !reportParsingProgress {
                    let percent = (Double(min(self.doneCount,self.missingCount))/Double(self.missingCount))
                    self.progress?.update(state: .progressing(percent), message: .updatingInfo)
                }
                self.currentState = .ready
                // if did something and not in force mode, schedule another batch
                if force {
                    self.progress?.update(state: .complete)
                    self.currentState = .complete
                }else{
                    self.updateRecords(count: count, force: false)
                    self.currentState = .ready
                }
            }else{
                if firstMissingCheck {
                    Logger.app.info("No logFile requires updating")
                }
                self.progress?.update(state: .complete)
                if self.doneCount > 0 {
                    NotificationCenter.default.post(name: .localFileListChanged, object: nil)
                }
                // nothing done, ready for more
                self.currentState = .complete
            }
        }
    }
    
    func addMissingRecordsFromLocal(){
        Self.search(in: [localFolder]){
            result in
            switch result {
            case .failure(let error):
                Logger.app.error("Failed to load local \(error.localizedDescription)")
            case .success(let urls):
                Self.scheduler.async {
                    let logs = FlightLogFileList(urls: urls)
                    self.add(aircrafts: urls)
                    self.addMinimum(flightLogFileList: logs)
                    self.updateRecords(count: 2)
                }
            }
        }
    }
    
    func filterMissing(urls: [URL]) -> [URL] {
        var rv : [URL] = []
        for url in urls {
            switch url.logFileType {
            case .aircraft:
                if let avionics = AvionicsSystem.from(jsonUrl: url),
                   self.managedAircrafts[ avionics.systemId ] != nil {
                    break
                }else{
                    rv.append(url)
                }
            case .log:
                let filename = url.lastPathComponent
                if self.managedFlightLogs[ filename ] == nil {
                    rv.append(url)
                }
            case .rpt:
                // always update rpt files
                rv.append(url)
            case .none:
                break
            }
        }
        return rv
    }
    
    func add(aircrafts: [URL]){
        var someNew : Int = 0
        var checked : Int = 0
        for url in aircrafts {
            if url.logFileType == .aircraft {
                checked += 1
                if let avionics = AvionicsSystem.from(jsonUrl: url) {
                    if let aircraft = self.managedAircrafts[ avionics.systemId ]  {
                        if aircraft.avionicsSystem != avionics {
                            aircraft.avionicsSystem = avionics
                            someNew += 1
                        }
                    }else{
                        AppDelegate.worker.sync {
                            Logger.app.info("Registering \(avionics)")
                            dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
                            let aircraft = AircraftRecord(context: self.persistentContainer.viewContext)
                            aircraft.avionicsSystem = avionics
                            aircraft.aircraftPerformance = Settings.shared.aircraftPerformance
                            self.managedAircrafts[avionics.systemId] = aircraft
                        }
                        someNew += 1
                    }
                }
            }
        }
        if someNew > 0 {
            Logger.app.info("Found \(someNew) aircrafts to add")
            AppDelegate.worker.sync {
                self.saveContext()
            }
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
    /// - Returns: number of new flights added (0 if all already there)
    @discardableResult
    func addMinimum(flightLogFileList : FlightLogFileList, completion : @escaping () -> Void = {} ) -> Int{
        dispatchPrecondition(condition: .onQueue(Self.scheduler))
        var someNew : Int = 0
        self.progress?.update(state: .start, message: .addingFiles)
        var index : Double = 0.0
        let indexTotal : Double = Double(flightLogFileList.count)
        
        var lastTime = Date()
        
        for flightLog in flightLogFileList.flightLogFiles {
            let filename = flightLog.name
            if filename.isFlightLogFile {
                if let existingRecord = self.managedFlightLogs[filename] {
                    // replace if parsed or if flightlog not populated
                    if flightLog.isParsed || existingRecord.flightLog == nil {
                        existingRecord.flightLog = flightLog
                    }
                    index += 1.0
                }else{
                    AppDelegate.worker.sync {
                        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
                        let fileInfo = FlightLogFileRecord(context: self.persistentContainer.viewContext)
                        fileInfo.organizer = self
                        fileInfo.log_file_name = filename
                        fileInfo.flightLog = flightLog
                        fileInfo.parseAndUpdate(quick: true)
                        if fileInfo.recordStatus == .empty {
                            Logger.app.info("Saving new empty record \(filename)")
                        }else{
                            Logger.app.info("Creating dependend \(fileInfo.recordStatus) record \(filename)")
                            //fileInfo.ensureDependentRecords(delaySave: true)
                        }
                        DispatchQueue.synchronized(self){
                            self.managedFlightLogs[ filename ] = fileInfo
                            someNew += 1
                            index += 1.0
                        }
                        if Date().timeIntervalSince(lastTime) > 1.0 {
                            lastTime = Date()
                            NotificationCenter.default.post(name: .localFileListChanged, object: self)
                        }
                    }
                    self.progress?.update(state: .progressing(index / indexTotal), message: .addingFiles)
                }
            }
        }
        self.progress?.update(state: .complete, message: .addingFiles)
        if someNew > 0 {
            AppDelegate.worker.sync{
                Logger.app.info("Added \(someNew) record for new local files")
                self.saveContext()
            }
            NotificationCenter.default.post(name: .localFileListChanged, object: self)
            NotificationCenter.default.post(name: .newLocalFilesDiscovered, object: self)
        }else{
            Logger.app.info("No missing local file in \(flightLogFileList.count) checked")
        }
        return someNew
    }
    
    func delete(info : FlightLogFileRecord){
        if let name = info.log_file_name {
            self.managedFlightLogs.removeValue(forKey: name)
            info.delete()
            self.persistentContainer.viewContext.delete(info)
            self.saveContext()
            NotificationCenter.default.post(name: .localFileListChanged, object: nil)
        }
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

        self.managedFlightLogs = [:]
        self.managedAircrafts = [:]
    }
    
    func deleteLocalFilesAndDatabase() {
        self.deleteAndResetDatabase()
        do {
            var count = 0
            let files = try FileManager.default.contentsOfDirectory(atPath: self.localFolder.path)
            for file in files{
                if file.isFlightLogFile {
                    count += 1
                    try FileManager.default.removeItem(at: self.localFolder.appendingPathComponent(file))
                }
            }
            Logger.app.info("Deleted \(count) out of \(files.count) files")
        }catch{
            Logger.app.error("Failed to look at content for delete")
        }
        
    }
    
    //MARK: - Upload File management
    
    func buildUploadList(viewController : UIViewController) {
        let list = self.flightLogFileRecords(request: .flightsOnly){
            record in
            if (record.recordStatus == .quickParsed || record.recordStatus == .parsed) {
                if Settings.shared.flystoEnabled && record.flystoStatus != .uploaded {
                    return true
                }
                if Settings.shared.savvyEnabled && record.savvyStatus != .uploaded {
                    return true
                }
            }
            return false
        }
        let count = Settings.shared.uploadBatchCount
        let todo = Array(list.prefix(min(count, list.count)))
        Logger.ui.info("\(list.count) / \(self.managedFlightLogs.count) potential to upload, will upload \(todo.count)")
        RequestQueue.shared.add(records: todo, viewController: viewController)
        
    }
    
    //MARK: - Aggregated Data
    /// Maintained full history of aggregatedData.
    /// When records are updated this will be update. Can be nil to disable the aggregation all together
    var aggregatedData : AggregatedDataOrganizer? = nil //AggregatedDataOrganizer(databaseName: "flights.db", table: "aggregatedData")
    
    //MARK: - Log Files discovery
    var localFolder : URL = { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }()
    var cloudFolder : URL? = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")
    
    func flightLogFile(name: String) -> FlightLogFile? {
        return FlightLogFile(url: self.localFolder.appendingPathComponent(name))
    }
    
    static public func search(in urls: [URL], completion: (Result<[URL],Error>) -> Void){
        for url in urls {
            let requireAccess = url.startAccessingSecurityScopedResource()
            defer {
                if requireAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            var error :NSError? = nil
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error){
                (dirurl) in
                var found : [URL] = []
                
                var isDirectory : ObjCBool = false
                if FileManager.default.fileExists(atPath: dirurl.path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue{
                        
                        let keys : [URLResourceKey] = [.nameKey, .isDirectoryKey]
                        
                        guard let fileList = FileManager.default.enumerator(at: dirurl, includingPropertiesForKeys: keys) else {
                            completion(Result.failure(OrganizerError.failedToReadFolder))
                            return
                        }
                        
                        for case let file as URL in fileList {
                            if file.logFileType != .none {
                                found.append(file)
                            }
                            if file.lastPathComponent == "data_log" && file.hasDirectoryPath {
                                self.search(in: [file]) {
                                    result in
                                    switch result {
                                    case .success(let more):
                                        found.append(contentsOf: more)
                                    case .failure(let error):
                                        completion(.failure(error))
                                    }
                                }
                            }
                        }
                    }else{
                        if dirurl.logFileType != .none {
                            found.append(dirurl)
                        }
                    }
                }
                completion(Result.success(found))
            }
        }
    }

    
    //MARK: - Update local file list
    
    private func copyLogFile(file : URL, dest : URL) -> Bool {
        var someNew : Bool = false
        if !FileManager.default.fileExists(atPath: dest.path) {
            do {
                try FileManager.default.copyItem(at: file, to: dest)
                Logger.app.info("copied \(file.lastPathComponent) to \(dest.path.truncated(limit:64))")
                someNew = true
            } catch {
                Logger.app.error("failed to copy \(file.lastPathComponent) to \(dest.path)")
            }
        }else{
            Logger.app.info("Already copied \(file.lastPathComponent)")
        }
        return someNew
    }
    private func copyRptFile(file : URL, destFolder : URL ) -> Bool{
        var someNew : Bool = false
        if let avionics = AvionicsSystem(url: file),
           let json = try? JSONEncoder().encode(avionics) {
            let dest = destFolder.appendingPathComponent(avionics.uniqueFileName)
            if !FileManager.default.fileExists(atPath: dest.path) {
                do {
                    try json.write(to: dest)
                    Logger.app.info("Created \(dest.lastPathComponent) from \(file.lastPathComponent)")
                    someNew = true
                }catch{
                    Logger.app.error("Failed to create \(dest.lastPathComponent)")
                }
            }else{
                Logger.app.info("Already created \(dest.lastPathComponent)")
            }
        }else{
            Logger.app.error("Failed to parse \(file.lastPathComponent)")
        }
        return someNew
    }
    
    enum LogSelectionMethod {
        case allMissingFromFolder // Automatically look for files missing in a folder
        case sinceLatestImportedFile // Only import files after the latest imported file
        case selectedFile([URL]) // Only import specified files
        case afterDate(Date) // Only import files after the specified date
    }

    /// Main entry point to find files to import and copy them locally, typically an SD Card
    /// optionally will process and create records in the database for new files
    /// - Parameters:
    ///   - urls: url to look for new file.
    ///   - process: if true will also sync cloud and add to the database new files, use false for testing
    func copyMissingFilesToLocal(urls : [URL], method : LogSelectionMethod, process : Bool = true) {
        Logger.app.info("Starting import \(method)")
        Self.search(in: urls ){
            result in
            switch result {
            case .success(let logurls):
                self.importAndAddRecordsForFiles(urls: logurls, method: method, process: process)
            case .failure(let error):
                Logger.app.error("Failed to find url \(error.localizedDescription)")
            }
        }
    }
    
    func importAndAddRecordsForFiles(urls: [URL], method: LogSelectionMethod, process : Bool = true){
        let someNew : Bool = self.importFiles(urls: urls, method: method)
        if someNew {
            if process {
                Logger.app.info("Local File list has update")
                self.addMissingRecordsFromLocal()
                self.syncCloud()
            }
        }
        else {
            Logger.app.info("Import found no new files")
            NotificationCenter.default.post(name: .noFileDiscovered, object: self)
        }
    }
    
    func buildImportList(urls : [URL], method :LogSelectionMethod) -> [URL]{
        var rv : [URL] = []
        
        for url in urls {
            var shouldInclude = false
            switch method {
            case .afterDate(let from):
                if let guessedDate = url.logFileGuessedDate,
                   guessedDate >= from {
                    shouldInclude = true
                }
            case .allMissingFromFolder:
                shouldInclude = true
            case .selectedFile(let selectedUrls):
                if selectedUrls.contains(url) {
                    shouldInclude = true
                }
            case .sinceLatestImportedFile:
                if let first = self.first(request: .all) {
                    if let guessedDate = url.logFileGuessedDate,
                       let firstGuessedDate = first.guessedDate{
                        shouldInclude = (guessedDate >= firstGuessedDate)
                    }
                }else{
                    // If no log at all, import all
                    shouldInclude = true
                }
            }
            if shouldInclude {
                rv.append(url)
            }
        }
        Logger.app.info("Found \(rv.count) new files out of \(urls.count)")
        return rv
    }
    
    /// Import (copy to local container) files missing according to selection Method
    /// - Parameters:
    ///   - urls: list of files to import
    ///   - method: selection method
    func importFiles(urls : [URL], method : LogSelectionMethod) -> Bool {
        let destFolder = self.localFolder
        var someNew : Bool = false
        
        let importList = self.buildImportList(urls: urls, method: method)

        for url in importList {
            if url.logFileType == .rpt {
                if self.copyRptFile(file: url,destFolder: destFolder) {
                    someNew = true
                }
            }else{
                let dest = destFolder.appendingPathComponent(url.lastPathComponent)
                if self.copyLogFile(file: url, dest: dest) {
                    someNew = true
                }
            }
        }
        return someNew
    }
    
    //MARK: - cloudKit Records management
    
    private static let enableCloudKit : Bool = false
    
    private func createPersistentCloudContainer() -> NSPersistentCloudKitContainer? {
        guard Self.enableCloudKit else { return nil }
        
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        let container = NSPersistentCloudKitContainer(name: "FlightLogModel")

        guard let cloudStoreDescription = container.persistentStoreDescriptions.first,
              let url = cloudStoreDescription.url else { return nil }
        
        var path = url.deletingLastPathComponent().path
        path.append("/FlightLogModelCloud.sqlite")
        cloudStoreDescription.url = URL(fileURLWithPath: path)
        cloudStoreDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "net.ro-z.flightlogstats.records")
        
        container.loadPersistentStores() {
            (storeDescription,error) in
            if let error = error {
                Logger.app.error("Failed to load \(error.localizedDescription)")
            }else{
                let path = storeDescription.url?.path ?? ""
                Logger.app.info("Loaded store \(storeDescription.type) \(path.truncated(limit: 64))")
                container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                self.checkForUpdates()
            }
        }
        return container
    }
    
    lazy var persistentCloudContainer : NSPersistentCloudKitContainer? = {
        return self.createPersistentCloudContainer()
    }()

    func saveCloudContext() {
        guard Self.enableCloudKit else { return }
        
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        
        if let cloudContext = persistentCloudContainer?.viewContext,
           cloudContext.hasChanges {
            do {
                try cloudContext.save()
            }catch{
                let nserror = error as NSError
                Logger.app.error("Failed to save cloud contexts \(nserror)")
            }
        }
    }

    private var managedCloudAircrafts : [SystemId:AircraftRecord] = [:]
    // LogFilename to fuelrecord
    private var managedCloudFuelRecords : [String:FlightFuelRecord] = [:]
    
    private func loadFromCloudContainer() {
        self.loadAircraftFromCloudContainer()
        self.loadFuelRecordsFromCloudContainer()
        self.saveAircraftsToCloudContainer()
    }
    
    private func saveAircraftsToCloudContainer() {
        guard let cloudContainer = self.persistentCloudContainer else { return }
        var needSave = false
        for (systemId,aircraft) in self.managedAircrafts {
            if self.managedCloudAircrafts[systemId] == nil {
                let cloudAircraft = AircraftRecord(context: cloudContainer.viewContext)
                cloudAircraft.setupAsCopy(of: aircraft)
                needSave = true
                self.managedCloudAircrafts[cloudAircraft.systemId] = cloudAircraft
            }
        }
        if needSave {
            self.saveCloudContext()
        }
    }
    
    private func loadAircraftFromCloudContainer() {
        guard let cloudContainer = self.persistentCloudContainer else { return }
        
        let fetchRequest = AircraftRecord.fetchRequest()
        
        do {
            let fetchAircrafts : [AircraftRecord] = try cloudContainer.viewContext.fetch(fetchRequest)
            var added = 0
            let existing = self.managedCloudAircrafts.count
            for aircraft in fetchAircrafts {
                if let systemId = aircraft.system_id {
                    added += 1
                    aircraft.container = self
                    self.managedAircrafts[systemId] = aircraft
                }
            }
            NotificationCenter.default.post(name: .aircraftListChanged, object: self)
            Logger.app.info("Loaded \(fetchAircrafts.count) Aircrafts from Cloud: existing \(existing) added \(added)")
        }catch{
            Logger.app.error("Failed to query for aircrafts")
        }
    }

    private func loadFuelRecordsFromCloudContainer() {
        guard let cloudContainer = self.persistentCloudContainer else { return }
        
        let fetchRequest = FlightFuelRecord.fetchRequest()
        
        do {
            let fuelRecords : [FlightFuelRecord] = try cloudContainer.viewContext.fetch(fetchRequest)
            var added = 0
            let existing = self.managedCloudFuelRecords.count
            for record in fuelRecords {
                if let logFileName = record.log_file_name {
                    added += 1
                    record.container = self
                    self.managedCloudFuelRecords[logFileName] = record
                }
            }
            NotificationCenter.default.post(name: .aircraftListChanged, object: self)
            Logger.app.info("Loaded \(fuelRecords.count) Aircrafts: existing \(existing) added \(added)")
        }catch{
            Logger.app.error("Failed to query for fuelRecord")
        }
    }
    func deleteAndResetCloudDatabase() {
        guard Self.enableCloudKit, let cloudContainer = self.persistentCloudContainer else { return }
        
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        
        self.deletePersistentStores(for: cloudContainer)
        self.persistentCloudContainer = self.createPersistentCloudContainer()

        self.managedFlightLogs = [:]
        self.managedAircrafts = [:]
    }

    //MARK: - sync with cloud drive files
    private var cachedQuery : NSMetadataQuery? = nil
    private var cachedLocalFlightLogList : FlightLogFileList? = nil
    
    func syncCloud() {
        self.cloudFolder = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")
        guard cloudFolder != nil else {
            Logger.sync.info("iCloud not setup, skipping sync")
            return
        }
        self.progress?.update(state: .progressing(0.0), message: .iCloudSync)
        Self.search(in: [localFolder]){
            result in
            switch result {
            case .failure(let error):
                Logger.sync.error("Failed to find files \(error.localizedDescription)")
            case .success(let urls):
                DispatchQueue.main.async {
                    // this needs to run on the main thread
                    self.syncCloud(with: FlightLogFileList(urls: urls))
                }
            }
        }
    }
    
    private func syncCloud(with local : FlightLogFileList ) {
        // query for iCloud need to run on main queue
        dispatchPrecondition(condition: .onQueue(.main))
        
        self.cachedLocalFlightLogList = local
        
        if let already = self.cachedQuery?.isGathering, already {
            Logger.sync.info("Query already gathering")
            return
        }else {
            Logger.sync.info("Query starting")
        }
        // stop if already exists
        self.cachedQuery?.stop()
        self.cachedQuery = NSMetadataQuery()
        if let query = self.cachedQuery {
            NotificationCenter.default.addObserver(self, selector: #selector(didFinishGathering), name: .NSMetadataQueryDidFinishGathering, object: nil)
            
            query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
            query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemPathKey)
            
            if query.start() == false {
                Logger.sync.error("Failed to start query for cloud files")
            }
        }
        AppDelegate.worker.async {
            self.loadFromCloudContainer()
        }
    }

    @objc func didFinishGathering() {
        if let query = self.cachedQuery {
            
            var cloudUrls : [URL] = []
            
            for item in query.results {
                if let url = (item as? NSMetadataItem)?.value(forAttribute: NSMetadataItemURLKey) as? URL {
                    cloudUrls.append(url)
                }
            }
            
            Logger.sync.info("Found \(cloudUrls.count) files on iCloud")
            
            self.progress?.update(state: .complete, message: .iCloudSync)
            
            Self.search(in: [self.localFolder]){
                result in
                switch result{
                case .failure(let error):
                    Logger.app.error("Failed to load local \(error.localizedDescription)")
                case .success(let urls):
                    AppDelegate.worker.async {
                        self.syncCloudLogic(localUrls: urls, cloudUrls: cloudUrls)
                    }

                }
            }
        }
    }
    
    func syncCloudLogic(localUrls : [URL], cloudUrls : [URL], completion : @escaping () -> Void = {  } ){
        var existingInLocal : Set<String> = []
        var existingInCloud : Set<String> = []
        
        // Gather what is in what to check what is missing
        for cloudUrl in cloudUrls {
            let lastComponent = cloudUrl.lastPathComponent
            if lastComponent.logFileType != .none {
                existingInCloud.insert(lastComponent)
            }
        }
        
        for localUrl in localUrls {
            let lastComponent = localUrl.lastPathComponent
            if lastComponent.logFileType != .none {
                existingInLocal.insert(lastComponent)
            }
        }
        // copy local to cloud
        var copyLocalToCloud : [URL] = []
        var copyCloudToLocal : [NSFileAccessIntent] = []
        
        for cloudUrl in cloudUrls {
            let lastComponent = cloudUrl.lastPathComponent
            if lastComponent.logFileType != .none {
                if !existingInLocal.contains(lastComponent) {
                    Logger.sync.info( "copy to local \(cloudUrl.lastPathComponent)")
                    copyCloudToLocal.append(NSFileAccessIntent.readingIntent(with: cloudUrl))
                }
            }
        }
        
        var copiedToCloud : Int = 0
        
        let totalCount = Double(localUrls.count + cloudUrls.count)
        var done : Double = 0
        
        for localUrl in localUrls {
            let lastComponent = localUrl.lastPathComponent
            self.progress?.update(state: .progressing(done/totalCount), message: .iCloudSync)
            done += 1.0
            if lastComponent.logFileType != .none {
                if !existingInCloud.contains(lastComponent) {
                    copyLocalToCloud.append(localUrl)
                    if let cloud = cloudFolder?.appendingPathComponent(localUrl.lastPathComponent) {
                        copiedToCloud += 1
                        Logger.sync.info( "copy to cloud \(localUrl.lastPathComponent)")
                        do {
                            if !FileManager.default.fileExists(atPath: cloud.path) {
                                try FileManager.default.copyItem(at: localUrl, to: cloud)
                            }else{
                                Logger.sync.info("Already copied \(cloud.lastPathComponent), skipping")
                            }
                        }catch{
                            Logger.sync.error("Failed to copy to cloud \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
        
        if copiedToCloud == 0 {
            Logger.sync.info("Nothing new in local to copy to cloud")
        }
        if copyCloudToLocal.count > 0 {
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(with: copyCloudToLocal, queue: self.queue){
                error in
                if error == nil {
                    do {
                        for intent in copyCloudToLocal {
                            self.progress?.update(state: .progressing(done/totalCount), message: .iCloudSync)
                            done += 1.0
                            try FileManager.default.copyItem(at: intent.url, to: self.localFolder.appendingPathComponent(intent.url.lastPathComponent))
                        }
                        self.addMissingRecordsFromLocal()
                    }catch{
                        Logger.sync.error("Failed to copy from cloud \(error.localizedDescription)")
                    }
                }else{
                    if let error = error {
                        Logger.sync.error("Failed to coordinate \(error.localizedDescription)")
                    }
                }
                completion()
            }
        }else{
            Logger.sync.info("Nothing new in cloud to copy to local")
            completion()
        }
        self.progress?.update(state: .complete, message: .iCloudSync)
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

