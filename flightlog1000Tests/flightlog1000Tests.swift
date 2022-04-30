//
//  flightlog1000Tests.swift
//  flightlog1000Tests
//
//  Created by Brice Rosenzweig on 18/04/2022.
//

import XCTest
@testable import FlightLog1000
import CoreData
import OSLog

extension Logger {
    public static let test = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "test")
}

class flightlog1000Tests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testLogInterpret() throws {
        guard let url = Bundle(for: type(of: self)).url(forResource: "log_210623_141501_TEST1", withExtension: "csv")
        else {
            XCTAssertTrue(false)
            return
        }

        let log = FlightLogFile(url: url)!
        log.parse()
        if let data = log.data {
            let identifiers = data.datesStrings(for: ["AtvWpt"])
            print( identifiers )
        
            
            let speedPower = data.datesDoubles(for: FlightLogFile.fields([.GndSpd,.IAS,.E1_PctPwr,.AltMSL]))

            if let engineOn = speedPower.dropFirst(field: FlightLogFile.field(.E1_PctPwr), matching: { $0 > 0 }),
               let moving = engineOn.dropFirst(field: FlightLogFile.field(.GndSpd),matching: { $0 > 0 }) {
                XCTAssertLessThan(engineOn.count, data.count)
                XCTAssertLessThan(moving.count, engineOn.count)
            }else{
                XCTAssertTrue(false)
            }
        }
        
        
    }
    
    func testLogFileDiscovery() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
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
                expectation.fulfill()
            }
        }
    }
    
    func testOrganizerSyncCloud() throws {
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
        
        let expectation = XCTestExpectation(description: "container cloud loaded")

        // set up cloud folder to be bundle, should copy eveyrthing locally
        organizer.localFolder = writeableUrl
        organizer.cloudFolder = bundleUrl
        
        //organizer.syncCloud(with: )
        expectation.fulfill()
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
        
        guard let url = Bundle(for: type(of: self)).url(forResource: "log_210623_141501_TEST1", withExtension: "csv")
        else {
            XCTAssertTrue(false)
            return
        }

        let log = FlightLogFile(url: url)!
        log.parse()
        organizer.add(flightLogFileList: FlightLogFileList(logs: [log]))
        organizer.saveContext()
        XCTAssertEqual(organizer.managedFlightLogs.count,1)
        let reload = FlightLogOrganizer()
        reload.persistentContainer = container
        XCTAssertEqual(reload.managedFlightLogs.count,0)
        reload.loadFromContainer()
        XCTAssertEqual(reload.managedFlightLogs.count,1)
        organizer.loadFromContainer()
        XCTAssertEqual(reload.managedFlightLogs.count,1)
        expectation.fulfill()
    }
}

