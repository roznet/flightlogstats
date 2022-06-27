//
//  TestAnalysis.swift
//  flightlog1000Tests
//
//  Created by Brice Rosenzweig on 23/06/2022.
//

import XCTest
@testable import FlightLog1000
import RZUtils

final class TestAnalysis: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testFuelAnalysis() throws {
        let aircraft = Aircraft(fuelMax: FuelQuantity(total: 92.0),
                                fuelTab: FuelQuantity(total: 60.0),
                                gph: 17.0)
        let fuelInputs = FuelAnalysis.Inputs(targetFuel: FuelQuantity(total: 70.0), addedfuel: FuelQuantity(left: 29.0, right: 31.0, unit: GCUnit.liter()))
        let fuelAnalysis = FuelAnalysis(aircraft: aircraft,
                                        current: FuelQuantity(left: 30.5, right: 32.2, unit: GCUnit.usgallon()),
                                        inputs: fuelInputs)
        
        XCTAssertEqual( fuelAnalysis.addedTotal.totalWithUnit.description, "78.6 gal")
        let second = GCNumberWithUnit(unit: GCUnit.second(), andValue: fuelAnalysis.addedTotalEndurance)
        let lost = GCNumberWithUnit(unit: GCUnit.second(), andValue: fuelAnalysis.addedLostEndurance)
        XCTAssertEqual(second.description, "04:37:14")
        XCTAssertEqual(lost.description, "47:28")
    }


}
