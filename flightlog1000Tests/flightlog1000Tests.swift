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
import RZFlight
import FMDB
import CoreLocation
import TabularData
import RZUtils

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

    func testFlightData() {
        guard let url = Bundle(for: type(of: self)).url(forResource: "log_210623_141501_TEST1", withExtension: "csv"),
              let data = FlightData(url: url)
        else {
            XCTAssertTrue(false)
            return
        }

        let m = RZPerformance.start()
        do {
            var csvtypes : [String:CSVType] = [:]
            for field in data.doubleFields {
                csvtypes[field.rawValue] = .double
            }
            for field in data.stringFields {
                csvtypes[field.rawValue] = .string
            }
            var csvoption = CSVReadingOptions()
            if( false ){
                let tab = try DataFrame(contentsOfCSVFile: url, columns: nil, types: csvtypes, options: csvoption)
                print(tab)
                Logger.test.info("Tabular \(m!.description)")
            }
        }catch{
            Logger.test.info("Tabular error \(error.localizedDescription)")
        }
        
        let identifiers = data.datesStrings(for: [.AtvWpt])
        print( identifiers )
        let speedPower = data.datesDoubles(for: [.GndSpd,.IAS,.E1_PctPwr,.AltMSL])

        if let engineOn = speedPower.dropFirst(field: .E1_PctPwr, matching: { $0 > 0 }),
           let moving = engineOn.dropFirst(field: .GndSpd,matching: { $0 > 0 }) {
            XCTAssertLessThan(engineOn.count, data.count)
            XCTAssertLessThan(moving.count, engineOn.count)
        }else{
            XCTAssertTrue(false)
        }

    }
    
    func testLogInterpret() throws {
        guard let url = Bundle(for: type(of: self)).url(forResource: "log_210623_141501_TEST1", withExtension: "csv")
        else {
            XCTAssertTrue(false)
            return
        }

        let log = FlightLogFile(url: url)!
        log.parse()
        let summary = log.flightSummary
        print( summary! )

        let route = log.legs
        print( route )
        
        print( FlightLogFile.Field.AfcsOn.localizedDescription )
        
        let dataSource = FlightLegsDataSource(legs: route)
        print( dataSource.fields.map { $0.order } )
        //for table each column should have same number of row
        dataSource.computeGeometry()
        print( dataSource.contentSize)
        XCTAssertEqual(dataSource.rowsHeight.count * dataSource.columnsWidth.count, dataSource.cellSizes.count)
        XCTAssertEqual(dataSource.rowsHeight.count * dataSource.columnsWidth.count, dataSource.attributedCells.count)
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
    
    func testKnownAirports(){
        let url = Bundle.main.url(forResource: "airports", withExtension: "db")

        XCTAssertNotNil(url)
        if let url = url {
            let db = FMDatabase(url: url)
            db.open()
            
            let known = KnownAirports(db:db)
            let cases = [ ("EGTF", 51.3504028, -0.5617803, "Woking", 1),
                          ("EGPN", 56.4537125,    -3.0180488, "Dundee", 1),
                          ("KSAF", 35.617, -106.089, "Santa Fe", 3),]
            for test in cases {
                let coord = CLLocationCoordinate2D(latitude: test.1, longitude: test.2)
                let nearest = known.nearest(coord: coord, db: db)
                XCTAssertNotNil(nearest)
                guard let nearest = nearest else { continue }
                //
                XCTAssertEqual(nearest.icao, test.0)
                XCTAssertEqual(nearest.city, test.3)
                XCTAssertEqual(nearest.runways.count, test.4)
            }
            db.close()
        }
        
    }
}

