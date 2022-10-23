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
    
    /// quick helper to find log file
    /// - Parameter dirurl: url to search
    /// - Returns: list of found files
    func findLocalLogFiles(dirurl : URL) -> [URL] {
        var found : [URL] = []
        
        var isDirectory : ObjCBool = false
        if FileManager.default.fileExists(atPath: dirurl.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                let keys : [URLResourceKey] = [.nameKey, .isDirectoryKey]
                
                guard let fileList = FileManager.default.enumerator(at: dirurl, includingPropertiesForKeys: keys) else {
                    return []
                }
                
                for case let file as URL in fileList {
                    if file.isLogFile {
                        found.append(file)
                    }
                }
            }else{
                if dirurl.isLogFile {
                    found.append(dirurl)
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
    
    
    func testLogFileDiscovery() throws {
        // This will test that:
        //   1. we find list of files in local directory
        //   2. logic if we remove one file from known ones that it identifies missing one
        
        guard let url = Bundle(for: type(of: self)).resourceURL
        else {
            XCTAssertTrue(false)
            return
        }
        
        let expectation = XCTestExpectation(description: "found files")
        FlightLogOrganizer.search(in: [url]){
            result in
            switch result {
                
            case .failure(let error):
                Logger.test.error("failed to search \(error.localizedDescription)")
                XCTAssertTrue(false)
            case .success(let urls):
                let loglist = FlightLogFileList(urls: urls)
                XCTAssertGreaterThan(loglist.flightLogFiles.count, 0)
                
                XCTAssertNotNil(urls.last)
                if let last = urls.last {
                    let urlsMinusLast = [URL](urls.dropLast())
                    let incompleteLogList = FlightLogFileList(urls: urlsMinusLast)
                    let missingLogList = incompleteLogList.missing(from: loglist)
                    XCTAssertEqual(missingLogList.flightLogFiles.count, 1)
                    if let missingLog = missingLogList.flightLogFiles.last {
                        XCTAssertEqual(last.lastPathComponent, missingLog.name)
                    }
                }
            }
            expectation.fulfill()
        }
        self.wait(for: [expectation], timeout: TimeInterval(10.0))
    }
    
    func DISABLEtestOrganizerSyncCloud() throws {
        // This will test that
        //   1. logic of copying missing from from cloud works: cloud proxied by bundle path, and local by a testLocal folder initially empty
        //   2. after copying form cloud (bundle path) the coredata container updated
        
        guard let bundleUrl = Bundle(for: type(of: self)).resourceURL
        else {
            XCTAssertTrue(false)
            return
        }
        
        let organizer = FlightLogOrganizer()
        let writeableUrl = organizer.localFolder.appendingPathComponent("testLocal")
        
        do {
            if FileManager.default.fileExists(atPath: writeableUrl.path) {
                try FileManager.default.removeItem(at: writeableUrl)
            }
        }catch{
            Logger.test.error("Failed to remove directory for testing \(error.localizedDescription)")
            XCTAssertNil(error)
        }
        
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
        
        // set up cloud folder to be bundle, should copy eveyrthing locally
        organizer.localFolder = writeableUrl
        organizer.cloudFolder = bundleUrl
        
        let cloudUrls = self.findLocalLogFiles(dirurl: bundleUrl)
        var localUrls = self.findLocalLogFiles(dirurl: writeableUrl)
        
        organizer.syncCloudLogic(localUrls: localUrls, cloudUrls: cloudUrls)
        localUrls = self.findLocalLogFiles(dirurl: writeableUrl)
        // check we copied all
        XCTAssertEqual(localUrls.count, cloudUrls.count)
        
        // now remove one from localUrls, and assuming local is cloud, make sure syncCloud will copy missing over
        if let last = localUrls.last {
            do {
                try FileManager.default.removeItem(at: last)
                localUrls = self.findLocalLogFiles(dirurl: writeableUrl)
                XCTAssertEqual(localUrls.count, cloudUrls.count - 1)
                organizer.syncCloudLogic(localUrls: cloudUrls, cloudUrls: localUrls)
                localUrls = self.findLocalLogFiles(dirurl: writeableUrl)
                XCTAssertEqual(localUrls.count, cloudUrls.count)
            }catch{
                XCTAssertTrue(false)
            }
        }else{
            XCTAssertTrue(false)
        }
    }
    
    func testOrganizer() throws {
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
        organizer.saveContext()
        XCTAssertEqual(organizer.count,1)
        
        if let info = organizer.flightLogFileInfos.first {
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
        XCTAssertNotNil(reload.flightLogFileInfos.first?.fuel_record)
        if let info = reload.flightLogFileInfos.first,
           let record = info.fuel_record {
            XCTAssertEqual( record.target_fuel, 75.0)
            record.target_fuel = 80.0
            organizer.saveContext()
        }
        
        let reload2 = FlightLogOrganizer()
        reload2.persistentContainer = container
        XCTAssertEqual(reload2.count,0)
        reload2.loadFromContainer()
        XCTAssertNotNil(reload2.flightLogFileInfos.first?.fuel_record)
        if let info = reload2.flightLogFileInfos.first,
           let record = info.fuel_record {
            XCTAssertEqual( record.target_fuel, 80.0)
        }
        
        expectation.fulfill()
    }
}
