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
    private(set) var managedFlightLogList : [String:FlightLogFileInfo] = [:]
    
    public static var shared = FlightLogOrganizer()
    
    private let queue = OperationQueue()
    
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
            let existing = self.managedFlightLogList.count
            for info in fetchedInfo {
                if let filename = info.log_file_name {
                    if self.managedFlightLogList[filename] == nil {
                        added += 1
                        self.managedFlightLogList[filename] = info
                    }
                }
            }
            Logger.app.info("Loaded \(fetchedInfo.count) existing \(existing) added \(added) ")
        }catch{
            Logger.app.error("Failed to query for files")
        }
    }

    func add(flightLog : FlightLogFile){
        let filename = flightLog.name
        if filename.isLogFile {
            if let existing = self.managedFlightLogList[filename] {
                // replace if parsed or if flightlog not populated
                if flightLog.isParsed || existing.flightLog == nil {
                    existing.flightLog = flightLog
                }
            }else{
                let fileInfo = FlightLogFileInfo(context: self.persistentContainer.viewContext)
                flightLog.updateFlightLogFileInfo(info: fileInfo)
                self.managedFlightLogList[ filename ] = fileInfo
            }
        }
    }
    
    //MARK: - Log Files discovery
    var localFolder : URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    let cloudFolder : URL? = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")
    
    static public func search(in urls: [URL], completion : (_ : [URL]) -> Void){
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
                    return
                }
                var found : [URL] = []
                
                for case let file as URL in fileList {
                    if file.isLogFile {
                        found.append(file)
                    }
                    if file.lastPathComponent == "data_log" && file.hasDirectoryPath {
                        self.search(in: [file]) {
                            logs in
                            found.append(contentsOf: logs)
                        }
                    }
                }
                completion(found)
            }
        }
    }

    
    //MARK: - Update local file list
    
    func copyMissingToLocal(urls : [URL]) {
        let destFolder = self.localFolder
        
        Self.search(in: urls ){
            logurls in
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
        }
    }
    
    //MARK: - sync with cloud
    private var cachedQuery : NSMetadataQuery? = nil
    private var cachedLocalFlightLogList : FlightLogFileList? = nil
    
    func syncCloud(with local : FlightLogFileList) {
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
                            Logger.app.info( "copy to local \(cloudUrl)")
                            copyCloudToLocal.append(NSFileAccessIntent.readingIntent(with: cloudUrl))
                        }
                    }
                }
                
                for localUrl in localUrls {
                    let lastComponent = localUrl.lastPathComponent
                    if lastComponent.isLogFile {
                        if !existingInCloud.contains(lastComponent) {
                            copyLocalToCloud.append(localUrl)
                            if let cloud = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents").appendingPathComponent(localUrl.lastPathComponent) {
                                Logger.app.info( "copy to cloud \(localUrl)")
                                do {
                                    try FileManager.default.copyItem(at: localUrl, to: cloud)
                                }catch{
                                    Logger.app.error("Failed to copy to cloud \(error.localizedDescription)")
                                }
                            }
                        }
                    }
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
                                NotificationCenter.default.post(name: .localFileListChanged, object: nil)
                            }catch{
                                Logger.app.error("Failed to copy from cloud \(error.localizedDescription)")
                            }
                        }else{
                            if let error = error {
                                Logger.app.error("Failed to coordinate \(error.localizedDescription)")
                            }
                        }
                    }
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
