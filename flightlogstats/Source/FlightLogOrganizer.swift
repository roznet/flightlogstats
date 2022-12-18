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
    static let aircraftListChanged  : Notification.Name = Notification.Name("Notification.Name.AircraftListChanged")
}

class FlightLogOrganizer {
    
    enum OrganizerError : Error {
        case failedToReadFolder
    }
    public static var shared = FlightLogOrganizer()
    
    //MARK: - List management
    var flightLogFileInfos : [FlightLogFileRecord] {
        let list = Array(self.managedFlightLogs.values)
        return list.sorted { $0.isNewer(than: $1) }
    }
    
    var first : FlightLogFileRecord? {
        self.flightLogFileInfos.first
    }
    var firstNonEmpty : FlightLogFileRecord? {
        self.nonEmptyLogFileInfos.first
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
        for candidate in self.flightLogFileInfos.reversed() {
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
        for candidate in self.actualFlightLogFileInfos {
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
    func filter(filter : (FlightLogFileRecord) -> Bool) -> [FlightLogFileRecord] {
        var logs : [FlightLogFileRecord] = []
        for info in self.flightLogFileInfos {
            if filter(info) {
                logs.append(info)
            }
        }
        return logs
    }
    
    var nonEmptyLogFileInfos : [FlightLogFileRecord] {
        return self.filter() {
            info in
            return !info.isEmpty
        }
    }

    var actualFlightLogFileInfos : [FlightLogFileRecord] {
        return self.filter() {
            info in
            return info.isFlight
        }
    }

    //MARK: - Aircraft management
    
    func aircraft(systemId : SystemId, airframeName : String? = nil) -> AircraftRecord {
        if let rv = self.managedAircrafts[systemId] {
            return rv
        }else{
            let newAircraft = AircraftRecord(context: self.persistentContainer.viewContext)
            newAircraft.system_id = systemId
            newAircraft.airframe_name = airframeName
            // set default performance
            newAircraft.aircraftPerformance = Settings.shared.aircraftPerformance
            self.managedAircrafts[systemId] = newAircraft
            self.saveContext()
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
    private var managedFlightLogs : [String:FlightLogFileRecord] = [:]
    private var currentState : UpdateState = .complete
    private var missingCount : Int = 0
    private var doneCount : Int = 0
    private let queue = OperationQueue()

    /// managed aircrafts keyed of system_id
    typealias SystemId = AvionicsSystem.SystemId
    private var managedAircrafts : [SystemId:AircraftRecord] = [:]
    
    private var flightLogFileList : FlightLogFileList {
        let list = FlightLogFileList(logs: self.managedFlightLogs.values.compactMap { $0.flightLog }.sorted { $0.name > $1.name } )
        return list
    }

    lazy var persistentContainer : NSPersistentContainer = {
        let container = NSPersistentContainer(name: "FlightLogModel")
        container.loadPersistentStores() {
            (storeDescription,error) in
            if let error = error {
                Logger.app.error("Failed to load \(error.localizedDescription)")
            }else{
                let path = storeDescription.url?.path ?? ""
                Logger.app.info("Loaded store \(storeDescription.type) \(path)")
                container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                self.checkForUpdates()
            }
        }
        return container
    }()
    
    func saveContext() {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            }catch{
                let nserror = error as NSError
                Logger.app.error("Failed to load \(nserror)")
            }
        }
    }
    
    func checkForUpdates() {
        Settings.shared.databaseVersion = 1
    }
    
    func loadFromContainer() {
        self.loadAircraftFromContainer()
        self.loadLogsFromContainer()
    }
    
    private func loadLogsFromContainer() {
        let fetchRequest = FlightLogFileRecord.fetchRequest()
        
        do {
            let fetchedInfo : [FlightLogFileRecord] = try self.persistentContainer.viewContext.fetch(fetchRequest)
            var added = 0
            let existing = self.managedFlightLogs.count
            var needSave = false
            for info in fetchedInfo {
                if let filename = info.log_file_name {
                    if self.managedFlightLogs[filename] == nil {
                        added += 1
                        info.container = self
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
            self.updateInfo(count: 1)
        }catch{
            Logger.app.error("Failed to query for files")
        }
    }

    private func loadAircraftFromContainer() {
        let fetchRequest = AircraftRecord.fetchRequest()
        
        do {
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
    
    func updateInfo(count : Int = 1, force : Bool = false) {
        guard currentState != .updatingInfoFromData else { return }
        let firstMissingCheck : Bool = (currentState == .complete)
        currentState = .updatingInfoFromData
        AppDelegate.worker.async {
            var missing : [FlightLogFileRecord] = []
            for (_,info) in self.managedFlightLogs {
                if force || info.requiresParsing{
                    if firstMissingCheck, let log_file_name = info.log_file_name {
                        if !force {
                            Logger.app.info("Will update missing info for \(log_file_name)")
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
                        let requiresParsing = flightLog.requiresParsing
                        // only report parsing progress if few missing, if many, just report overall progress
                        if requiresParsing {
                            Logger.app.info("Parsing \(log_file_name)")
                        }
                        flightLog.parse(progress: reportParsingProgress ? self.progress : nil)
                        do {
                            try info.updateFromFlightLog(flightLog: flightLog)
                        }catch{
                            info.recordStatus = .error
                            Logger.app.error("Failed to update log \(error.localizedDescription)")
                        }
                        
                        NotificationCenter.default.post(name: .logFileRecordUpdated, object: info)
                        if requiresParsing {
                            flightLog.clear()
                        }
                        done.append(log_file_name)
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
                    self.updateInfo(count: count, force: false)
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
    
    func addMissingFromLocal(){
        Self.search(in: [localFolder]){
            result in
            switch result {
            case .failure(let error):
                Logger.app.error("Failed to load local \(error.localizedDescription)")
            case .success(let urls):
                let logs = FlightLogFileList(urls: urls)
                self.add(aircrafts: urls)
                self.add(flightLogFileList: logs)
                self.updateInfo(count: 1)
            }
        }
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
                        Logger.app.info("Registering \(avionics)")
                        let aircraft = AircraftRecord(context: self.persistentContainer.viewContext)
                        aircraft.avionicsSystem = avionics
                        aircraft.aircraftPerformance = Settings.shared.aircraftPerformance
                        self.managedAircrafts[avionics.systemId] = aircraft
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
    
    
    
    func add(flightLogFileList : FlightLogFileList){
        var someNew : Int = 0
        self.progress?.update(state: .start, message: .addingFiles)
        var index : Double = 0.0
        let indexTotal : Double = Double(flightLogFileList.count)
        
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "Parsing", attributes: .concurrent)
        
        for flightLog in flightLogFileList.flightLogFiles {
            
            let filename = flightLog.name
            if filename.isLogFile {
                if let existing = self.managedFlightLogs[filename] {
                    // replace if parsed or if flightlog not populated
                    if flightLog.isParsed || existing.flightLog == nil {
                        existing.flightLog = flightLog
                    }
                    index += 1.0
                }else{
                    group.enter()
                    queue.async {
                        let fileInfo = FlightLogFileRecord(context: self.persistentContainer.viewContext)
                        fileInfo.container = self
                        flightLog.updateFlightLogFileInfo(info: fileInfo)
                        DispatchQueue.synchronized(self){
                            self.managedFlightLogs[ filename ] = fileInfo
                            someNew += 1
                            index += 1.0
                        }
                        self.progress?.update(state: .progressing(index / indexTotal), message: .addingFiles)
                        group.leave()
                    }
                }
            }
        }
        group.notify(queue: AppDelegate.worker){
            self.progress?.update(state: .complete, message: .addingFiles)
            if someNew > 0 {
                Logger.app.info("Found \(someNew) local files to add")
                self.saveContext()
                NotificationCenter.default.post(name: .localFileListChanged, object: self)
            }else{
                Logger.app.info("No missing local file in \(flightLogFileList.count) checked")
            }
        }
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
    
    func deleteAndResetDatabase() {
        let coordinator = self.persistentContainer.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            if let url = store.url {
                do {
                    try coordinator.destroyPersistentStore(at: url, type: NSPersistentStore.StoreType(rawValue: store.type))
                }catch{
                    Logger.app.error("failed to reset store \(error)")
                }
            }
        }

        self.managedFlightLogs = [:]
    }
    
    func deleteLocalFilesAndDatabase() {
        self.deleteAndResetDatabase()
        do {
            var count = 0
            let files = try FileManager.default.contentsOfDirectory(atPath: self.localFolder.path)
            for file in files{
                if file.isLogFile {
                    count += 1
                    try FileManager.default.removeItem(at: self.localFolder.appendingPathComponent(file))
                }
            }
            Logger.app.info("Deleted \(count) out of \(files.count) files")
        }catch{
            Logger.app.error("Failed to look at content for delete")
        }
        
    }
    
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
                        if dirurl.isLogFile {
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
                Logger.app.info("copied \(file.lastPathComponent) to \(dest.path)")
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
    
    /// Main logic to identify which files to import and copy, typically an SD Card
    /// - Parameters:
    ///   - urls: url to look for new file.
    ///   - process: if true will also sync cloud and add to the database new files, use false for testing
    func copyMissingToLocal(urls : [URL], process : Bool = true) {
        let destFolder = self.localFolder
        
        Self.search(in: urls ){
            result in
            switch result {
            case .success(let logurls):
                var someNew : Bool = false
                for url in logurls {
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
                if someNew {
                    if process {
                        Logger.app.info("Local File list has update")
                        self.addMissingFromLocal()
                        self.syncCloud()
                    }
                }
            case .failure(let error):
                Logger.app.error("Failed to find url \(error.localizedDescription)")
            }
        }
    }
    
    //MARK: - sync with cloud
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
                self.syncCloud(with: FlightLogFileList(urls: urls))
            }
        }
    }
    
    private func syncCloud(with local : FlightLogFileList ) {
        // look in cloud what we are missing locally
        if self.cachedQuery != nil {
            self.cachedQuery?.stop()
        }
        self.cachedLocalFlightLogList = local
        
        if let already = self.cachedQuery?.isGathering, already {
            Logger.sync.info("Query already gathering")
        }
        
        self.cachedQuery = NSMetadataQuery()
        if let query = self.cachedQuery {
            NotificationCenter.default.addObserver(self, selector: #selector(didFinishGathering), name: .NSMetadataQueryDidFinishGathering, object: nil)
            
            query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
            query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemPathKey)
            query.start()
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
    
    func syncCloudLogic(localUrls : [URL], cloudUrls : [URL]){
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
                        self.addMissingFromLocal()
                    }catch{
                        Logger.sync.error("Failed to copy from cloud \(error.localizedDescription)")
                    }
                }else{
                    if let error = error {
                        Logger.sync.error("Failed to coordinate \(error.localizedDescription)")
                    }
                }
            }
        }else{
            Logger.sync.info("Nothing new in cloud to copy to local")
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
    var isLogFile : Bool { self.logFileType == .log }
    
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
        if self.isLogFile {
            let d = (self as NSString).deletingPathExtension
            if let guess = d.components(separatedBy: "_").last {
                return guess
            }
        }
        return nil
    }
}

extension URL {
    typealias LogFileType = String.LogFileType
    var logFileType : LogFileType { return self.lastPathComponent.logFileType }
    var isLogFile : Bool { return self.lastPathComponent.isLogFile }
}

