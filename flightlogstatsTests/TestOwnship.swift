//
//  TestOwnship.swift
//  FlightLogStatsTests
//
//  The one-minute lead vector drawn from the live position.
//

import XCTest
@testable import FlightLogStats
import CoreLocation

final class TestOwnship: XCTestCase {

    private let knot : CLLocationSpeed = 1852.0 / 3600.0

    func testLeadAfterOneMinute() throws {
        let start = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)

        // 60 kt east for a minute is 1 nm, one arc minute of longitude at the equator
        let east = OwnshipVector(coordinate: start, course: 90.0, speed: 60.0 * knot)
        let lead = try XCTUnwrap(east.lead)
        XCTAssertEqual(lead.latitude, 0.0, accuracy: 1.0e-9)
        XCTAssertEqual(lead.longitude, 1.0 / 60.0, accuracy: 1.0e-4)

        // 120 kt north is 2 nm, two arc minutes of latitude anywhere
        let north = OwnshipVector(coordinate: CLLocationCoordinate2D(latitude: 51.5, longitude: -0.2), course: 0.0, speed: 120.0 * knot)
        let leadNorth = try XCTUnwrap(north.lead)
        XCTAssertEqual(leadNorth.latitude, 51.5 + 2.0 / 60.0, accuracy: 1.0e-4)
        XCTAssertEqual(leadNorth.longitude, -0.2, accuracy: 1.0e-9)

        // the distance is speed times lead time, along the course
        let from = CLLocation(latitude: 48.0, longitude: 2.0)
        let diagonal = OwnshipVector(coordinate: from.coordinate, course: 225.0, speed: 100.0 * knot)
        let leadDiagonal = try XCTUnwrap(diagonal.lead)
        let travelled = from.distance(from: CLLocation(latitude: leadDiagonal.latitude, longitude: leadDiagonal.longitude))
        XCTAssertEqual(travelled, 100.0 * knot * 60.0, accuracy: 100.0 * knot * 60.0 * 0.005)
        XCTAssertLessThan(leadDiagonal.latitude, 48.0)
        XCTAssertLessThan(leadDiagonal.longitude, 2.0)
    }

    func testNoLeadWhenStoppedOrTrackUnknown() {
        let here = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.2)
        XCTAssertNil(OwnshipVector(coordinate: here, course: 90.0, speed: 0.5).lead)
        XCTAssertNil(OwnshipVector(coordinate: here, course: nil, speed: 60.0 * knot).lead)
        XCTAssertNil(OwnshipVector(coordinate: here, course: 90.0, speed: nil).lead)

        // Core Location reports unknown course and speed as negative values
        let invalid = CLLocation(coordinate: here, altitude: 0.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0,
                                 course: -1.0, speed: -1.0, timestamp: Date())
        let vector = OwnshipVector(location: invalid)
        XCTAssertNil(vector.course)
        XCTAssertNil(vector.speed)
        XCTAssertNil(vector.lead)
    }

    func testLeadAcrossAntimeridian() throws {
        let vector = OwnshipVector(coordinate: CLLocationCoordinate2D(latitude: 0.0, longitude: 179.99), course: 90.0, speed: 120.0 * knot)
        let lead = try XCTUnwrap(vector.lead)
        XCTAssertEqual(lead.longitude, 179.99 + 2.0 / 60.0 - 360.0, accuracy: 1.0e-3)
        XCTAssertGreaterThanOrEqual(lead.longitude, -180.0)
    }
}
