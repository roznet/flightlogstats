//
//  TestParsingCsv.swift
//  flightlog1000Tests
//
//  Created by Brice Rosenzweig on 23/05/2022.
//

import XCTest
@testable import FlightLog1000

class TestParsingCsv: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func streamForString(string : String) -> InputStream? {
        if let data = string.data(using: .utf8) {
            return InputStream(data: data)
        }else{
            return nil
        }
    }
    
    func testBasics() throws {
        let string = "#aa,b=\"1.2\", c=\"a b\"\r\n#yyy,  degrees,  deg F,     kt\n  Lcl Date,   Latitude,   E1 CHT4,  IAS,\n   , 51.2,  300.23, 100.0\n2022-04-16,   , 320.0,    110"
        guard let stream = self.streamForString(string: string) else { XCTAssertTrue(false); return }
        
        let data = try FlightData(inputStream: stream)
        print( data )
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
