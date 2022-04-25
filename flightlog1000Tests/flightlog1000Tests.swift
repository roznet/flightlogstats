//
//  flightlog1000Tests.swift
//  flightlog1000Tests
//
//  Created by Brice Rosenzweig on 18/04/2022.
//

import XCTest
@testable import FlightLog1000
import CoreData

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

        let log = FlightLogFile(url: url)
        log.parse()
        if let data = log.data {
            let identifiers = data.datesStrings(for: ["AtvWpt"])
            print( identifiers )
        
            
            let speedPower = data.datesDoubles(for: [FlightLogFile.Field.GndSpd.rawValue,
                                                     FlightLogFile.Field.IAS.rawValue,
                                                     FlightLogFile.Field.E1_PctPwr.rawValue,
                                                     FlightLogFile.Field.AltMSL.rawValue])
            let speedWind = data.datesDoubles(for: ["GndSpd","E1 %Pwr","AltMSL","WndSpd","WndDr"])

            let engineOn = speedPower.dropFirst(field: "E1 %Pwr") { $0 > 0 }
            let moving = engineOn?.dropFirst(field: "GndSpd") { $0 > 0 }
            
            print( "Start: \(data.dates.first)")
            print( "End: \(data.dates.last)")
            print( "Moved: \(moving?.first(field: "GndSpd"))")
            
        }
        
        
    }
    
    func testLogParsingSearch() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        guard let url = Bundle(for: type(of: self)).resourceURL
        else {
            XCTAssertTrue(false)
            return
        }
        
        let expectation = XCTestExpectation(description: "found files")
        FlightLogOrganizer.search(in: [url]){
            logs in
            let loglist = FlightLogFileList(urls: logs)
            XCTAssertGreaterThan(loglist.flightLogFiles.count, 0)
            
            expectation.fulfill()
        }
    }
    
    func testOrganizer() throws {
        let organizer = FlightLogOrganizer()
        /*
        let container = NSPersistentContainer(name: "FlightLogModel")
        let description = NSPersistentStoreDescription()
        description.url = URL(fileURLWithPath: "/dev/null")
        container.persistentStoreDescriptions = [description]
        organizer.persistentContainer = container
         */
        let expectation = XCTestExpectation(description: "container loaded")
        
        guard let url = Bundle(for: type(of: self)).url(forResource: "log_210623_141501_TEST1", withExtension: "csv")
        else {
            XCTAssertTrue(false)
            return
        }

        let log = FlightLogFile(url: url)
        log.parse()
        organizer.add(flightLog: log)
    }


}
