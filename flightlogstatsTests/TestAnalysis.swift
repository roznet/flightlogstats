//
//  TestAnalysis.swift
//  flightlog1000Tests
//
//  Created by Brice Rosenzweig on 23/06/2022.
//

import XCTest
@testable import FlightLogStats
import RZUtils

final class TestAnalysis: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testFuelAnalysis() throws {
        let aircraft = AircraftPerformance(fuelMax: FuelTanks(total: 92.0),
                                fuelTab: FuelTanks(total: 60.0),
                                gph: 17.0)
        let fuelInputs = FuelAnalysis.Inputs(targetFuel: FuelTanks(total: 70.0), addedfuel: FuelTanks(left: 29.0, right: 31.0, unit: GCUnit.liter()), totalizerStartFuel: FuelTanks(total: 92.0))
        
        let fuelAnalysis = FuelAnalysis(aircraft: aircraft,
                                        current: FuelTanks(left: 30.5, right: 32.2, unit: GCUnit.usgallon()),
                                        totalizer: FuelTanks(total: 92.0),
                                        inputs: fuelInputs)
        
        XCTAssertEqual( fuelAnalysis.addedTotal.totalWithUnit.description, "78.6 gal")
        let second = GCNumberWithUnit(unit: GCUnit.second(), andValue: fuelAnalysis.addedTotalEndurance)
        let lost = GCNumberWithUnit(unit: GCUnit.second(), andValue: fuelAnalysis.addedLostEndurance)
        XCTAssertEqual(second.description, "04:37:14")
        XCTAssertEqual(lost.description, "47:28")
    }

    func testEdgeCases() {
        let aircraft = AircraftPerformance(fuelMax: FuelTanks(total: 92.0),
                                fuelTab: FuelTanks(total: 60.0),
                                gph: 17.0)
        let fuelInputs = FuelAnalysis.Inputs(targetFuel: FuelTanks(total: 60.0),
                                             addedfuel: FuelTanks(left: 25.0, right: 25.0, unit: GCUnit.usgallon()),
                                             totalizerStartFuel: FuelTanks(total: 92.0))
        var fuelAnalysis = FuelAnalysis(aircraft: aircraft,
                                        current: FuelTanks(left: 29.0, right: 31.0, unit: GCUnit.usgallon()),
                                        totalizer: FuelTanks(total: 92.0),
                                        inputs: fuelInputs)
        // first case: current.total equal target.total but current.left < target.left, don't add anything
        
        XCTAssertEqual(fuelAnalysis.targetFuel, fuelInputs.targetFuel)

        // second case: current.total below target.total but current.right > target.right, only add to left
        
        fuelAnalysis = FuelAnalysis(aircraft: aircraft,
                                   current: FuelTanks(left: 28.0, right: 31.0, unit: GCUnit.usgallon()),
                                    totalizer: FuelTanks(total: 92.0),
                                   inputs: fuelInputs)
        XCTAssertEqual(fuelAnalysis.targetFuel, fuelInputs.targetFuel)

        for one in [
            FuelTanks(left: 0.0, right: -1.0),
            FuelTanks(left: -1.0, right: -1.0),
            FuelTanks(left: 1.0, right: -1.0),
            FuelTanks(left: 2.0, right: -1.0),
        ] {
            XCTAssertGreaterThanOrEqual(one.positiveOnly.total, 0.0)
        }
        
    }

}
