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

    func testLogParsing() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        guard let url = Bundle(for: type(of: self)).url(forResource: "log_210623_141501_TEST1", withExtension: "csv")
        else {
            XCTAssertTrue(false)
            return
        }
        
        let loglist = FlightLogList(directory: url.deletingLastPathComponent())
        print( "\(loglist)" )
        
        do {
            let log = try FlightLog(url:url)
            log.parse()
        }catch{
            XCTAssertTrue(false)
        }

    }


}
