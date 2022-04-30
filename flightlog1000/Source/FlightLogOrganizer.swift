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
}

class FlightLogOrganizer {
    
    enum OrganizerError : Error {
        case failedToReadFolder
    }
    private(set) var managedFlightLogs : [String:FlightLogFileInfo] = [:]
    
    public static var shared = FlightLogOrganizer()
    private let queue = OperationQueue()
    
    enum UpdateState {
        case ready
        case updatingInfoFromData
    }
    private var currentState : UpdateState = .ready

    var flightLogFileList : FlightLogFileList {
        let list = FlightLogFileList(logs: self.managedFlightLogs.values.compactMap { $0.flightLog } )
        return list
    }
    
    
    //MARK: - containers
    
    lazy var persistentContainer : NSPersistentContainer = {
        let container = NSPersistentContainer(name: "FlightLogModel")
        container.loadPersistentStores() {
            (storeDescription,error) in
            if let error = error {
                Logger.app.error("Failed to load \(error.localizedDescription)")
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
    
    func loadFromContainer() {
        let fetchRequest = FlightLogFileInfo.fetchRequest()
        
        do {
            let fetchedInfo : [FlightLogFileInfo] = try self.persistentContainer.viewContext.fetch(fetchRequest)
            var added = 0
            let existing = self.managedFlightLogs.count
            for info in fetchedInfo {
                if let filename = info.log_file_name {
                    if self.managedFlightLogs[filename] == nil {
                        added += 1
                        self.managedFlightLogs[filename] = info
                    }
                }
            }
            NotificationCenter.default.post(name: .localFileListChanged, object: self)
            Logger.app.info("Loaded \(fetchedInfo.count) existing \(existing) added \(added) ")
            self.updateInfo(count: 1)
        }catch{
            Logger.app.error("Failed to query for files")
        }
    }

    func updateInfo(count : Int = 1) {
        guard currentState == .ready else { return }
        currentState = .updatingInfoFromData
        AppDelegate.worker.async {
            var missing : [FlightLogFileInfo] = []
            for (_,info) in self.managedFlightLogs {
                if !info.isParsed {
                    missing.append(info)
                }
            }
            if !missing.isEmpty {
                var done : Int = 0
                for info in missing[..<min(count,missing.count)] {
                    if let log_file_name = info.log_file_name, info.flightLog == nil {
                        info.flightLog = self.flightLogFile(name: log_file_name)
                    }
                    
                    if let flightLog = info.flightLog {
                        let alreadyParsed = flightLog.isParsed
                        flightLog.parse()
                        flightLog.updateFlightLogFileInfo(info: info)
                        if !alreadyParsed {
                            flightLog.clear()
                        }
                        done += 1
                    }
                }
                Logger.app.info("Updated \(done) info")
                self.saveContext()
                self.currentState = .ready
                // if did something, schedule another batch
                self.updateInfo(count: count)
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
                self.add(flightLogFileList: logs)
                self.updateInfo(count: 1)
            }
        }
    }
    
    func add(flightLogFileList : FlightLogFileList){
        var someNew : Int = 0
        for flightLog in flightLogFileList.flightLogFiles {
            let filename = flightLog.name
            if filename.isLogFile {
                if let existing = self.managedFlightLogs[filename] {
                    // replace if parsed or if flightlog not populated
                    if flightLog.isParsed || existing.flightLog == nil {
                        existing.flightLog = flightLog
                    }
                }else{
                    let fileInfo = FlightLogFileInfo(context: self.persistentContainer.viewContext)
                    flightLog.updateFlightLogFileInfo(info: fileInfo)
                    self.managedFlightLogs[ filename ] = fileInfo
                    someNew += 1
                }
            }
        }
        if someNew > 0 {
            Logger.app.info("Found \(someNew) local files to add")
            self.saveContext()
            NotificationCenter.default.post(name: .localFileListChanged, object: self)
        }else{
            Logger.app.info("No missing local file in \(flightLogFileList.count) checked")
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
            guard url.startAccessingSecurityScopedResource() else {
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            var error :NSError? = nil
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error){
                (dirurl) in
                let keys : [URLResourceKey] = [.nameKey, .isDirectoryKey]
                guard let fileList = FileManager.default.enumerator(at: dirurl, includingPropertiesForKeys: keys) else {
                    completion(Result.failure(OrganizerError.failedToReadFolder))
                    return
                }
                var found : [URL] = []
                
                for case let file as URL in fileList {
                    if file.isLogFile {
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
                completion(Result.success(found))
            }
        }
    }

    
    //MARK: - Update local file list
    
    func copyMissingToLocal(urls : [URL]) {
        let destFolder = self.localFolder
        
        Self.search(in: urls ){
            result in
            switch result {
            case .success(let logurls):
                var someNew : Bool = false
                for url in logurls {
                    let file = url
                    let dest = destFolder.appendingPathComponent(file.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: dest.path) {
                        do {
                            try FileManager.default.copyItem(at: file, to: dest)
                            Logger.app.info("copied \(file.lastPathComponent) to \(dest)")
                            someNew = true
                        } catch {
                            Logger.app.error("failed to copy \(file.lastPathComponent) to \(dest)")
                        }
                    }else{
                        Logger.app.info("Already copied \(file.lastPathComponent)")
                    }
                }
                if someNew {
                    NotificationCenter.default.post(name: .localFileListChanged, object: nil)
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
        guard cloudFolder != nil else {
            Logger.app.info("iCloud not setup, skipping sync")
            return
        }
        
        Self.search(in: [localFolder]){
            result in
            switch result {
            case .failure(let error):
                Logger.app.error("Failed to find files \(error.localizedDescription)")
            case .success(let urls):
                self.syncCloud(with: FlightLogFileList(urls: urls))
            }
        }
    }
    
    private func syncCloud(with local : FlightLogFileList) {
        // look in cloud what we are missing locally
        if self.cachedQuery != nil {
            self.cachedQuery?.stop()
        }
        self.cachedLocalFlightLogList = local
        
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
            
            if let localUrls = self.cachedLocalFlightLogList?.urls {
                var cloudUrls : [URL] = []
                
                for item in query.results {
                    if let url = (item as? NSMetadataItem)?.value(forAttribute: NSMetadataItemURLKey) as? URL {
                        cloudUrls.append(url)
                    }
                }
                var existingInLocal : Set<String> = []
                var existingInCloud : Set<String> = []

                // Gather what is in what to check what is missing
                for cloudUrl in cloudUrls {
                    let lastComponent = cloudUrl.lastPathComponent
                    if lastComponent.isLogFile {
                        existingInCloud.insert(lastComponent)
                    }
                }
                
                for localUrl in localUrls {
                    let lastComponent = localUrl.lastPathComponent
                    if lastComponent.isLogFile {
                        existingInLocal.insert(lastComponent)
                    }
                }
                // copy local to cloud
                var copyLocalToCloud : [URL] = []
                var copyCloudToLocal : [NSFileAccessIntent] = []

                for cloudUrl in cloudUrls {
                    let lastComponent = cloudUrl.lastPathComponent
                    if lastComponent.isLogFile {
                        if !existingInLocal.contains(lastComponent) {
                            Logger.app.info( "copy to local \(cloudUrl.lastPathComponent)")
                            copyCloudToLocal.append(NSFileAccessIntent.readingIntent(with: cloudUrl))
                        }
                    }
                }
                
                var copiedToCloud : Int = 0
                
                for localUrl in localUrls {
                    let lastComponent = localUrl.lastPathComponent
                    if lastComponent.isLogFile {
                        if !existingInCloud.contains(lastComponent) {
                            copyLocalToCloud.append(localUrl)
                            if let cloud = cloudFolder?.appendingPathComponent(localUrl.lastPathComponent) {
                                copiedToCloud += 1
                                Logger.app.info( "copy to cloud \(localUrl.lastPathComponent)")
                                do {
                                    try FileManager.default.copyItem(at: localUrl, to: cloud)
                                }catch{
                                    Logger.app.error("Failed to copy to cloud \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                }
                
                if copiedToCloud == 0 {
                    Logger.app.info("Nothing new in local to copy to cloud")
                }
                if copyCloudToLocal.count > 0 {
                    let coordinator = NSFileCoordinator()
                    coordinator.coordinate(with: copyCloudToLocal, queue: self.queue){
                        error in
                        if error == nil {
                            do {
                                for intent in copyCloudToLocal {
                                    try FileManager.default.copyItem(at: intent.url, to: self.localFolder.appendingPathComponent(intent.url.lastPathComponent))
                                }
                                self.addMissingFromLocal()
                            }catch{
                                Logger.app.error("Failed to copy from cloud \(error.localizedDescription)")
                            }
                        }else{
                            if let error = error {
                                Logger.app.error("Failed to coordinate \(error.localizedDescription)")
                            }
                        }
                    }
                }else{
                    Logger.app.info("Nothing new in cloud to copy to local")
                }
            }
        }
    }
}

extension String {
    var isLogFile : Bool { return self.hasPrefix("log_") && self.hasSuffix(".csv") }
}

extension URL {
    var isLogFile : Bool { return self.lastPathComponent.isLogFile }
}

extension FlightLogOrganizer {
    var count : Int { return managedFlightLogs.count }
    
    subscript(_ name : String) -> FlightLogFileInfo? {
        return self.managedFlightLogs[name]
    }
    
    subscript(log: FlightLogFile) -> FlightLogFileInfo? {
        return self.managedFlightLogs[log.name]
    }
}
