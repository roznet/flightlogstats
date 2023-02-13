//
//  TestOrganizer.swift
//  flightlog1000Tests
//
//  Created by Brice Rosenzweig on 03/06/2022.
//

import XCTest
@testable import FlightLogStats
import CoreData
import OSLog
import RZFlight
import FMDB
import CoreLocation
import RZUtils

class TestOrganizer: XCTestCase {
    
    func prepareAndClearFolder(url : URL) -> Bool {
        var isDirectory : ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else{
                Logger.test.error("\(url.path) is not a directory")
                return false
            }
            
            let keys : [URLResourceKey] = [.nameKey, .isDirectoryKey]
            
            guard let fileList = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else {
                return false
            }
            
            for case let file as URL in fileList {
                do {
                    if FileManager.default.fileExists(atPath: file.path) {
                        try FileManager.default.removeItem(at: file)
                    }
                }catch{
                    Logger.test.error("Failed to remove file for testing \(error.localizedDescription)")
                    return false
                }
            }
            
        }else{ // does not exist, create
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            }catch{
                Logger.test.error("Failed to create directory \(url.path)")
                return false
            }
        }
        return true
    }
    
    /// quick helper to find log file
    /// - Parameter dirurl: url to search
    /// - Returns: list of found files
    func findLocalLogFiles(url : URL, types : [String.LogFileType] ) -> [URL] {
        var found : [URL] = []
        
        var isDirectory : ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                let keys : [URLResourceKey] = [.nameKey, .isDirectoryKey]
                
                guard let fileList = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else {
                    return []
                }
                
                for case let file as URL in fileList {
                    if  types.contains(file.logFileType) {
                        found.append(file)
                    }
                }
            }
        }
        return found
    }
    
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
   
    // order array of URL by guessed date if possible
    func orderLogsByDate(urls : [URL]) -> [URL] {
        var ordered : [URL] = []
        for url in urls {
            if url.isLogFileTestFileToSkip {
                continue
            }
            if url.logFileGuessedDate != nil {
                ordered.append(url)
            }
        }
        ordered.sort {
            $0.logFileGuessedDate! < $1.logFileGuessedDate!
        }
        return ordered
    }
    func runImportTest(organizer: FlightLogOrganizer, urls : [URL], bundeUrl : URL){
        let writeableLocalUrl = organizer.localFolder
        let startUrls = self.findLocalLogFiles(url: bundeUrl, types: [.log])
        //var localUrls = self.findLocalLogFiles(url: writeableLocalUrl, types: [.log,.aircraft,.rpt])
       
        var orderedLogs = self.orderLogsByDate(urls: urls)
        var one : URL? = nil
        for url in orderedLogs {
            if url.isLogFileTestFileToSkip{
                continue
            }
            if url.isLogFile {
                one = url
                break
            }
        }
        guard let url = one else {
            XCTAssertTrue(false)
            return
        }
       
        // Import one file only
        var someNew = organizer.importFiles(urls: urls, method: .selectedFile([url]))
        XCTAssertTrue(someNew)
        var localUrls = self.findLocalLogFiles(url: writeableLocalUrl, types: [.log,.aircraft,.rpt])
        XCTAssertTrue(localUrls.count == 1)
        XCTAssertEqual(localUrls.first!.lastPathComponent,url.lastPathComponent)
        
        // now import everything since 2022
        //unix time for 2022-01-01 00:00:00 is 1640995200
        let date2022 = Date(timeIntervalSince1970: 1640995200)
        someNew = organizer.importFiles(urls: urls, method: .afterDate(date2022))
        XCTAssertTrue(someNew)
        localUrls = self.findLocalLogFiles(url: writeableLocalUrl, types: [.log,.rpt])
        orderedLogs = self.orderLogsByDate(urls: localUrls)
        XCTAssertEqual(orderedLogs.count, localUrls.count)
        //Note we don't test sinceLatestImportedFile because here we don't update
        //Records, so won't know which is latest date, we will test that case in syncCloud
        
        // Now import everything else
        someNew = organizer.importFiles(urls: urls, method: .allMissingFromFolder)
        XCTAssertTrue(someNew)
        localUrls = self.findLocalLogFiles(url: writeableLocalUrl, types: [.log,.rpt])
        XCTAssertTrue(localUrls.count == startUrls.count)
        
    }
    
    func testLogFileDiscovery() throws {
        // This will test that:
        //   1. we find list of files in local directory
        //   2. logic if we remove one file from known ones that it identifies missing one
        
        guard let bundleUrl : URL = Bundle(for: type(of: self)).resourceURL
        else {
            XCTAssertTrue(false)
            return
        }
        
        guard let organizer = self.createOrganizerWithMemoryContainer(localFolderName: "testDiscovery", cloudFolderName: nil)
        else {
            XCTAssertTrue(false)
            return
        }
        
        
        let expectation = XCTestExpectation(description: "found files")
        FlightLogOrganizer.search(in: [bundleUrl],
                                  completion:  {
            result in
            switch result {
                
            case .failure(let error):
                Logger.test.error("failed to search \(error.localizedDescription)")
                XCTAssertTrue(false)
            case .success(let urls):
                self.runImportTest(organizer: organizer, urls: urls, bundeUrl: bundleUrl)
            }
            expectation.fulfill()
        })
        self.wait(for: [expectation], timeout: TimeInterval(10.0))
    }
    
    func testLogFileNameGuesses(){
        guard let url = Bundle(for: type(of: self)).resourceURL
        else {
            XCTAssertTrue(false)
            return
        }
        let files = self.findLocalLogFiles(url: url, types: [.log,.rpt])
        let reconstructFormatter = DateFormatter()
        reconstructFormatter.dateFormat = "yyMMdd_HHmm"
        for file in files {
            let name = file.lastPathComponent
            // special case, not a date
            if name.hasPrefix("log_small") {
                continue
            }
            if let date = name.logFileGuessedDate {
                if name.logFileType == .log {
                    let rebuildPrefix = "log_\(reconstructFormatter.string(from: date))"
                    XCTAssertTrue(name.hasPrefix(rebuildPrefix))
                }else if name.logFileType == .rpt {
                    let rebuildPrefix = "rpt_\(reconstructFormatter.string(from: date))"
                    XCTAssertTrue(name.hasPrefix(rebuildPrefix))
                }
            }else{
                XCTAssertTrue(false, "bad date for \(name)")
            }
        }
    }
    func createOrganizerWithMemoryContainer(localFolderName : String, cloudFolderName : String?) -> FlightLogOrganizer? {
        let organizer = FlightLogOrganizer()
        let writeableBase =  FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let writeableLocalUrl = writeableBase.appendingPathComponent(localFolderName)
        organizer.localFolder = writeableLocalUrl
        var toClean : [URL] = [writeableLocalUrl]
        if let cloudFolderName = cloudFolderName {
            let writeableCloudUrl = writeableBase.appendingPathComponent(cloudFolderName)
            toClean.append(writeableCloudUrl)
            organizer.cloudFolder = writeableCloudUrl
        }
        Logger.test.info("Cleaning test folders")
        for writeableUrl in toClean {
            guard self.prepareAndClearFolder(url: writeableUrl) else {
                return nil
            }
            Logger.test.info("Cleaned and prepared \(writeableUrl.path)")
        }
        
        let container = NSPersistentContainer(name: "FlightLogModel")
        let description = NSPersistentStoreDescription()
        description.url = URL(fileURLWithPath: "/dev/null")
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores() {
            (storeDescription,error) in
            if let error = error {
                Logger.test.error("Failed to load \(error.localizedDescription)")
                return
            }
        }
        organizer.persistentContainer = container
        return organizer
    }
    func testOrganizerSyncCloud() throws {
        // This will test that
        //   1. logic of copying missing from from cloud works: cloud proxied by bundle path, and local by a testLocal folder initially empty
        //   2. after copying form cloud (bundle path) the coredata container updated
        
        guard let bundleUrl = Bundle(for: type(of: self)).resourceURL
        else {
            XCTAssertTrue(false)
            return
        }
        
        guard let organizer = self.createOrganizerWithMemoryContainer(localFolderName: "testLocal", cloudFolderName: "testCloud"),
              let writeableCloudUrl = organizer.cloudFolder
        else {
            XCTAssertTrue(false)
            return
        }
        
        // set up cloud folder to be bundle, should copy eveyrthing locally
        let writeableLocalUrl = organizer.localFolder
            
        // first try to copy to local what is missing
        organizer.copyMissingFilesToLocal(urls: [bundleUrl], method: .allMissingFromFolder, process: false)
        
        let startUrls = self.findLocalLogFiles(url: bundleUrl, types: [.log])
        var localUrls = self.findLocalLogFiles(url: writeableLocalUrl, types: [.log,.aircraft,.rpt])
        
        // +1 because should have one aircraft file
        XCTAssertEqual(startUrls.count+1, localUrls.count)
        
        var cloudUrls = self.findLocalLogFiles(url: writeableCloudUrl, types: [.log,.aircraft,.rpt])
        XCTAssertEqual(cloudUrls.count, 0)// start with nothing
        organizer.syncCloudLogic(localUrls: localUrls, cloudUrls: cloudUrls)
        cloudUrls = self.findLocalLogFiles(url: writeableCloudUrl, types: [.log,.aircraft,.rpt])
        
        XCTAssertEqual(localUrls.count, cloudUrls.count)
        
        // now remove one from localUrls, and assuming local is cloud, make sure syncCloud will copy missing over
        
        if let last = localUrls.last {
            do {
                Logger.test.info("Removing \(last.path)")
                try FileManager.default.removeItem(at: last)
                localUrls = self.findLocalLogFiles(url: writeableLocalUrl, types: [.log,.aircraft,.rpt])
                cloudUrls = self.findLocalLogFiles(url: writeableCloudUrl, types: [.log,.aircraft,.rpt])
                XCTAssertEqual(localUrls.count, cloudUrls.count - 1)
                let fileCopiedExpectation = XCTestExpectation(description: "Added the files")
                let recordAddedExpectation = XCTestExpectation(description: "Added the records")
                organizer.syncCloudLogic(localUrls: localUrls, cloudUrls: cloudUrls){
                    localUrls = self.findLocalLogFiles(url: writeableLocalUrl, types: [.log,.aircraft,.rpt])
                    XCTAssertEqual(localUrls.count, cloudUrls.count)
                    // +1 because should have one aircraft file
                    fileCopiedExpectation.fulfill()
                }
                
                NotificationCenter.default.addObserver(forName: .newLocalFilesDiscovered, object: organizer, queue: nil) {
                    _ in
                    XCTAssertEqual(cloudUrls.count, organizer.count+1)
                    XCTAssertEqual(cloudUrls.count, organizer.flightLogFileInfos(request: .all).count+1) // +1 because one file is not a log but avionics system file
                    recordAddedExpectation.fulfill()
                }
                self.wait(for: [recordAddedExpectation,fileCopiedExpectation], timeout: 50*60.0)
            }catch{
                XCTAssertTrue(false)
            }
        }else{
            XCTAssertTrue(false)
        }
        
        Logger.test.info("Cleaning test folders")
        for writeableUrl in [writeableCloudUrl, writeableLocalUrl] {
            guard self.prepareAndClearFolder(url: writeableUrl) else {
                XCTAssertTrue(false)
                return
            }
        }
    }
    
    func testOrganizer() {
        let expectation = self.expectation(description: "run organizer test")
        FlightLogOrganizer.scheduler.async {
            do {
                try self.runTestOrganizer()
            }catch{
                XCTAssertNil(error)
            }
            expectation.fulfill()
        }
        self.wait(for: [expectation], timeout: 10.0)
    }
    func runTestOrganizer() throws {
        let organizer = FlightLogOrganizer()
        
        let container = NSPersistentContainer(name: "FlightLogModel")
        let description = NSPersistentStoreDescription()
        description.url = URL(fileURLWithPath: "/dev/null")
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores() {
            (storeDescription,error) in
            if let error = error {
                Logger.test.error("Failed to load \(error.localizedDescription)")
            }
        }
        organizer.persistentContainer = container
        
        let expectation = XCTestExpectation(description: "container loaded")
        
        guard let url = Bundle(for: type(of: self)).url(forResource: TestLogFileSamples.flight1.rawValue, withExtension: "csv")
        else {
            XCTAssertTrue(false)
            return
        }
        
        let log = FlightLogFile(url: url)!
        log.parse()
        organizer.add(flightLogFileList: FlightLogFileList(logs: [log]))
        AppDelegate.worker.sync {
            organizer.saveContext()
            
            XCTAssertEqual(organizer.count,1)
            
            if let info = organizer.flightLogFileInfos(request: .all).first {
                let record = FlightFuelRecord(context: container.viewContext)
                record.target_fuel = 75.0
                info.fuel_record = record
                organizer.saveContext()
            }
            let reload = FlightLogOrganizer()
            reload.persistentContainer = container
            XCTAssertEqual(reload.count,0)
            reload.loadFromContainer()
            XCTAssertEqual(reload.count,1)
            organizer.loadFromContainer()
            XCTAssertEqual(reload.count,1)
            XCTAssertNotNil(reload.flightLogFileInfos(request: .all).first?.fuel_record)
            if let info = reload.flightLogFileInfos(request: .all).first,
               let record = info.fuel_record {
                XCTAssertEqual( record.target_fuel, 75.0)
                record.target_fuel = 80.0
                organizer.saveContext()
            }
            
            let reload2 = FlightLogOrganizer()
            reload2.persistentContainer = container
            XCTAssertEqual(reload2.count,0)
            reload2.loadFromContainer()
            XCTAssertNotNil(reload2.flightLogFileInfos(request: .all).first?.fuel_record)
            if let info = reload2.flightLogFileInfos(request: .all).first,
               let record = info.fuel_record {
                XCTAssertEqual( record.target_fuel, 80.0)
            }
        }
        expectation.fulfill()
    }
}

extension URL {
    var isLogFileTestFileToSkip : Bool {
        return self.isLogFile && self.lastPathComponent.hasPrefix("log_small")
    }
}
