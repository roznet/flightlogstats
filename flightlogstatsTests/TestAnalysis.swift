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
        let aircraft = AircraftPerformance(fuelMax: FuelTanks(total: 92.0, unit: UnitVolume.aviationGallon),
                                           fuelTab: FuelTanks(total: 60.0, unit: UnitVolume.aviationGallon),
                                gph: 17.0)
        let fuelInputs = FuelAnalysis.Inputs(targetFuel: FuelTanks(total: 70.0, unit: UnitVolume.aviationGallon),
                                             addedfuel: FuelTanks(left: 29.0, right: 31.0, unit: UnitVolume.liters),
                                             totalizerStartFuel: FuelTanks(total: 92.0, unit: UnitVolume.aviationGallon))
        
        let fuelAnalysis = FuelAnalysis(aircraftPerformance: aircraft,
                                        current: FuelTanks(left: 30.5, right: 32.2, unit: UnitVolume.aviationGallon),
                                        totalizer: FuelTanks(total: 92.0, unit: UnitVolume.aviationGallon),
                                        inputs: fuelInputs)
        
        
        
        XCTAssertEqual( DisplayContext().displayedValue(field: .FQtyT, measurement: fuelAnalysis.addedTotal.totalMeasurement.measurementDimension).string, "78.6 gal")
        let second = GCNumberWithUnit(unit: GCUnit.second(), andValue: fuelAnalysis.addedTotalEndurance)
        let lost = GCNumberWithUnit(unit: GCUnit.second(), andValue: fuelAnalysis.addedLostEndurance)
        XCTAssertEqual(second.description, "04:37:14")
        XCTAssertEqual(lost.description, "47:28")
    }

    func testEdgeCases() {
        let aircraft = AircraftPerformance(fuelMax: FuelTanks(total: 92.0, unit: UnitVolume.aviationGallon),
                                fuelTab: FuelTanks(total: 60.0, unit: UnitVolume.aviationGallon),
                                gph: 17.0)
        let fuelInputs = FuelAnalysis.Inputs(targetFuel: FuelTanks(total: 60.0, unit: UnitVolume.aviationGallon),
                                             addedfuel: FuelTanks(left: 25.0, right: 25.0, unit: UnitVolume.aviationGallon),
                                             totalizerStartFuel: FuelTanks(total: 92.0, unit: UnitVolume.aviationGallon))
        var fuelAnalysis = FuelAnalysis(aircraftPerformance: aircraft,
                                        current: FuelTanks(left: 29.0, right: 31.0, unit: UnitVolume.aviationGallon),
                                        totalizer: FuelTanks(total: 92.0, unit: UnitVolume.aviationGallon),
                                        inputs: fuelInputs)
        // first case: current.total equal target.total but current.left < target.left, don't add anything
        
        XCTAssertEqual(fuelAnalysis.targetFuel.totalMeasurement, fuelInputs.targetFuel.totalMeasurement)

        // second case: current.total below target.total but current.right > target.right, only add to left
        
        fuelAnalysis = FuelAnalysis(aircraftPerformance: aircraft,
                                   current: FuelTanks(left: 28.0, right: 31.0, unit: UnitVolume.aviationGallon),
                                    totalizer: FuelTanks(total: 92.0, unit: UnitVolume.aviationGallon),
                                   inputs: fuelInputs)
        XCTAssertEqual(fuelAnalysis.targetFuel.totalMeasurement, fuelInputs.targetFuel.totalMeasurement)

        for one in [
            FuelTanks(left: 0.0, right: -1.0, unit: UnitVolume.aviationGallon),
            FuelTanks(left: -1.0, right: -1.0, unit: UnitVolume.aviationGallon),
            FuelTanks(left: 1.0, right: -1.0, unit: UnitVolume.aviationGallon),
            FuelTanks(left: 2.0, right: -1.0, unit: UnitVolume.aviationGallon),
        ] {
            XCTAssertGreaterThanOrEqual(one.positiveOnly.total, 0.0)
        }
        
    }

    /// C11: equality must see a change in the left/right split, not only the total,
    /// or `FlightLogViewModel` does not rebuild the fuel table.
    func testFuelTanksEqualityPerTank() {
        let even = FuelTanks(left: 30.0, right: 30.0, unit: UnitVolume.aviationGallon)
        let moved = FuelTanks(left: 25.0, right: 35.0, unit: UnitVolume.aviationGallon)
        XCTAssertEqual(even.total, moved.total)
        XCTAssertNotEqual(even, moved)
        XCTAssertEqual(even, FuelTanks(total: 60.0, unit: UnitVolume.aviationGallon))
        // same quantity in another unit is still equal
        XCTAssertEqual(even.converted(to: UnitVolume.liters).totalMeasurement, even.totalMeasurement)

        let inputs = FuelAnalysis.Inputs(targetFuel: even, addedfuel: even, totalizerStartFuel: even)
        let movedInputs = FuelAnalysis.Inputs(targetFuel: even, addedfuel: moved, totalizerStartFuel: even)
        XCTAssertNotEqual(inputs, movedInputs)
    }

}
