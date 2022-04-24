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
    public static var shared = FlightLogOrganizer()
    
    private let queue = OperationQueue()
    private init(){
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
    
    func add(flightLog : FlightLog){
        let fileInfo = FlightLogFileInfo(context: self.persistentContainer.viewContext)
        
    }
    
    //MARK: - Log Files management
    var destFolder : URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    let cloud = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")
    
    func flightLogListFromLocal(completion : (_ : FlightLogList) -> Void) {
        FlightLog.search(in: [self.destFolder]){
            logs in
            let list = FlightLogList(logs: logs)
            completion(list)
        }
    }
    
    func copyMissingToLocal(urls : [URL]) {
        let destFolder = self.destFolder
        
        FlightLog.search(in: urls ){
            logs in
            var someNew : Bool = false
            for log in logs {
                let file = log.url
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
    
    private var query : NSMetadataQuery? = nil
    private var localFlightLogList : FlightLogList? = nil
    
    func syncCloud(with local : FlightLogList) {
        // look in cloud what we are missing locally
        if self.query != nil {
            self.query?.stop()
        }
        self.localFlightLogList = local
        
        self.query = NSMetadataQuery()
        if let query = self.query {
            NotificationCenter.default.addObserver(self, selector: #selector(didFinishGathering), name: .NSMetadataQueryDidFinishGathering, object: nil)
            
            query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
            query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemPathKey)
            query.start()
        }
    }

    @objc func didFinishGathering() {
        if let query = self.query {
            
            if let localUrls = (self.localFlightLogList?.flightLogs.map{$0.url}) {
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
                                    try FileManager.default.copyItem(at: intent.url, to: self.destFolder.appendingPathComponent(intent.url.lastPathComponent))
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
