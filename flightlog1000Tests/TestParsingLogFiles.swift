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
import RZUtils

extension Logger {
    public static let test = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "test")
}

enum TestLogFileSamples : String, CaseIterable {
    case empty = "log_220414_065328______.csv"
    case turnOnOnly = "log_220502_095923______.csv"
    case taxiOnly = "log_220502_135932_EGPN.csv"
    
    case smallLog = "log_small_sample.csv"
    case smallLogFixed = "log_small_sample_fixed.csv"
    case largeLog = "log_211204_102045_EGLL.csv" // 5.2Mb
    
    case preflight1 = "log_220416_161856_LFQA.csv"
    
    case flight1 = "log_210623_141501_TEST1" // 2.4Mb  date with slash
    case flight2 = "log_220417_125002_LFQA.csv" // 1.4Mb
    case flight3 = "log_220417_135002_LFAQ.csv" // 3.2Mb
    
    static var allSampleNames : [String] { return self.allCases.map { $0.rawValue } }
 }

class TestParsingLogFiles: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testFlightData() {
        guard let url = Bundle(for: type(of: self)).url(forResource: TestLogFileSamples.flight1.rawValue, withExtension: "csv"),
              let data = FlightData(url: url)
        else {
            XCTAssertTrue(false)
            return
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
        guard let url = Bundle(for: type(of: self)).url(forResource: TestLogFileSamples.flight1.rawValue, withExtension: "csv")
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
                let airport = known.nearest(coord: coord, db: db)
                XCTAssertNotNil(airport)
                guard let airport = airport else { continue }
                XCTAssertEqual(airport.icao, test.0 )
                //
                XCTAssertEqual(airport.icao, test.0)
                XCTAssertEqual(airport.city, test.3)
                XCTAssertEqual(airport.runways.count, test.4)
            }
            db.close()
        }
    }
}

