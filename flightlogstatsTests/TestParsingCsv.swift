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

    /// Synthetic log: one row per second from 13:00:00, constant fuel flow.
    func syntheticLog(rows : Int, fuelFlow : Double, fuelUnit : String = "gals", fuelLeft : Double = 20.0, fuelRight : Double = 20.0) -> String {
        var lines = [
            "#airframe_info,airframe_name=\"an\",system_id=\"sid\"",
            "#yyy-mm-dd, hh:mm:ss,   hh:mm, degrees, degrees, kt, \(fuelUnit), \(fuelUnit), gph",
            "Lcl Date,  Lcl Time, UTCOfst,  Latitude,    Longitude,  IAS, FQtyL, FQtyR, E1 FFlow",
        ]
        let start = 13*3600
        for i in 0..<rows {
            let t = start + i
            let time = String(format: "%02d:%02d:%02d", t / 3600, (t / 60) % 60, t % 60)
            lines.append("2022-05-02, \(time),  +00:00, 56.4534912,   -3.0175426, 100.0, \(fuelLeft), \(fuelRight), \(fuelFlow)")
        }
        return lines.joined(separator: "\n")
    }

    /// C7: the totaliser integrates flow over the real time between parsed rows, so a
    /// quick parse (one row in 300) agrees with the full parse.
    func testTotalizerQuickParse() throws {
        let flow = 12.0
        let string = self.syntheticLog(rows: 1201, fuelFlow: flow)

        for sampling in [1, 300] {
            guard let stream = self.streamForString(string: string) else { XCTFail(); return }
            let data = try FlightData(inputStream: stream, lineSamplingFrequency: sampling)
            guard let first = data.firstDate, let last = data.lastDate,
                  let total = data.doubleDataFrame(for: [.FTotalizerT]).last(field: .FTotalizerT)?.value else {
                XCTFail("no totalizer for sampling \(sampling)")
                continue
            }
            XCTAssertGreaterThan(data.count, 1)
            let expected = last.timeIntervalSince(first) * flow / 3600.0
            XCTAssertEqual(total, expected, accuracy: expected * 0.01, "sampling \(sampling)")
        }
    }

    /// C8: fuel quantities are converted from the log's unit to the store unit.
    func testFuelUnitFromLog() throws {
        for (unit, expected) in [("gals", UnitVolume.aviationGallon), ("L", UnitVolume.liters)] {
            let string = self.syntheticLog(rows: 10, fuelFlow: 0.0, fuelUnit: unit, fuelLeft: 20.0, fuelRight: 30.0)
            guard let stream = self.streamForString(string: string) else { XCTFail(); return }
            let data = try FlightData(inputStream: stream)
            XCTAssertEqual(FlightSummary.fuelUnit(in: data), expected)

            let summary = try FlightSummary(data: data)
            XCTAssertEqual(summary.fuelStart.unit, Settings.fuelStoreUnit)
            let inLogUnit = summary.fuelStart.converted(to: expected)
            XCTAssertEqual(inLogUnit.left, 20.0, accuracy: 1.0e-6, unit)
            XCTAssertEqual(inLogUnit.right, 30.0, accuracy: 1.0e-6, unit)
        }
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
