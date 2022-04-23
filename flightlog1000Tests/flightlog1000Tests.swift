//
//  flightlog1000Tests.swift
//  flightlog1000Tests
//
//  Created by Brice Rosenzweig on 18/04/2022.
//

import XCTest
@testable import FlightLog1000

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

        let log = FlightLog(url: url)
        log.parse()
        let identifiers = log.data?.strings(for: ["AtvWpt"])
        print( identifiers )
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
        FlightLog.search(in: [url]){
            logs in
            let loglist = FlightLogList(logs: logs)
            XCTAssertGreaterThan(loglist.flightLogs.count, 0)
            
            if let one = loglist.flightLogs.first {
                one.parse()
                print( one )
                if let speed = one.data?.timeSeries(for: ["GndSpd","E1 %Pwr","AltMSL"]) {
                    XCTAssertGreaterThan(speed.1.count,0)
                }
                
                if let speed = one.data?.timeSeries(for: ["GndSpd","E1 %Pwr","AltMSL","WndSpd","WndDr"]) {
                    XCTAssertGreaterThan(speed.1.count,0)
                }
            }
            expectation.fulfill()
        }
    }


}
