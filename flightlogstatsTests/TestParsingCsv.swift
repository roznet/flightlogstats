//
//  TestParsingCsv.swift
//  flightlog1000Tests
//
//  Created by Brice Rosenzweig on 23/05/2022.
//

import XCTest
@testable import FlightLogStats
import RZUtils
import TabularData
import OSLog

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
        let string = """
#airframe_info,airframe_name=\"an\",  system_id=\"sid\", c=\"a b\"
#yyy-mm-dd, hh:mm:ss,   hh:mm, ident, degrees, degrees, ft,     kt, deg F
Lcl Date,  Lcl Time, UTCOfst,  AtvWpt,      Latitude,    Longitude,  AltInd,  IAS, E1 CHT4
2022-05-02, 13:58:26,  +00:00,  A, 56.4534912,   -3.0175426,  300.23, 100.0,   240.0
2022-05-02, 13:58:27,  +00:00,  A, 56.4534950,   -3.0175436,  320.0,    110.0,  242.0
"""
        guard let stream = self.streamForString(string: string) else { XCTAssertTrue(false); return }
        
        let data = try FlightData(inputStream: stream)
        
        let doubleDf = data.doubleDataFrame()
        let categoricalDf = data.categoricalDataFrame()
        
        XCTAssertTrue(doubleDf.has(fields: [.E1_CHT4,.IAS]))
        XCTAssertTrue(categoricalDf.has(field: .AtvWpt))
        
        XCTAssertEqual(data.meta[.system_id], "sid")
        XCTAssertEqual(data.meta[.airframe_name], "an")
        
    }

    func disableTestDataFrame() {
        guard let url = Bundle(for: type(of: self)).url(forResource: TestLogFileSamples.smallLog.rawValue, withExtension: "csv"),
              let urlfixed = Bundle(for: type(of: self)).url(forResource: TestLogFileSamples.smallLog.rawValue, withExtension: "csv"),
              let data = FlightData(url: url)
        else {
            XCTAssertTrue(false)
            return
        }
        
        do {
            var csvtypes : [String:CSVType] = [:]
            for field in data.doubleFields {
                csvtypes[field.rawValue] = .double
            }
            for field in data.categoricalFields {
                csvtypes[field.rawValue] = .string
            }
            let csvoption = CSVReadingOptions()
            if( true ){
                let tab = try DataFrame(contentsOfCSVFile: urlfixed, columns: nil, types: csvtypes, options: csvoption)
                print(tab)
            }
        }catch{
            Logger.test.info("Tabular error \(error.localizedDescription)")
        }
    }

}
