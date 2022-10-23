//
//  TestAvionics.swift
//  FlightLogStatsTests
//
//  Created by Brice Rosenzweig on 23/10/2022.
//

import XCTest
@testable import FlightLogStats
import RZUtils

final class TestAvionics: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testParsing() throws {
        guard let url = Bundle(for: type(of: self)).url(forResource: "rpt_220706_135400_N122DR", withExtension: "csv"),
              let avionics = AvionicsSystem(url: url)
        else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(avionics.aircraftIdentifier, "N122DR")
        let json = try JSONEncoder().encode(avionics)
        if let str = String(data: json, encoding: .utf8) {
            print( str )
        }
    }
    

}
