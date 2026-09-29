//
//  Ownship.swift
//  FlightLogStats
//
//  The aircraft's own position from GPS, and where it will be after a lead time
//  (one minute) at the current ground speed and track. Pure: no location manager,
//  no view, so it is shared by every live map (Frequencies tab, Bingo live mode).
//

import Foundation
import CoreLocation
import RZFlight

struct OwnshipVector : Equatable {
    /// how far ahead the lead point is drawn
    static let defaultLeadTime : TimeInterval = 60.0
    /// below this ground speed (m/s, about 2 kt) the track is noise: no vector
    static let minimumSpeed : CLLocationSpeed = 1.0

    let coordinate : CLLocationCoordinate2D
    /// true track in degrees, nil if unknown
    let course : CLLocationDirection?
    /// ground speed in m/s, nil if unknown
    let speed : CLLocationSpeed?
    let leadTime : TimeInterval

    init(coordinate : CLLocationCoordinate2D, course : CLLocationDirection?, speed : CLLocationSpeed?, leadTime : TimeInterval = Self.defaultLeadTime) {
        self.coordinate = coordinate
        self.course = course
        self.speed = speed
        self.leadTime = leadTime
    }

    /// Core Location reports an invalid course or speed as a negative value
    init(location : CLLocation, leadTime : TimeInterval = Self.defaultLeadTime) {
        self.init(coordinate: location.coordinate,
                  course: location.course >= 0.0 ? location.course : nil,
                  speed: location.speed >= 0.0 ? location.speed : nil,
                  leadTime: leadTime)
    }

    /// Position after `leadTime` at the current speed and track, nil when not moving
    /// or the track is unknown
    var lead : CLLocationCoordinate2D? {
        guard let course = self.course, let speed = self.speed, speed >= Self.minimumSpeed else { return nil }
        // great circle, from RZFlight
        let lead = self.coordinate.pointFromBearingDistance(bearing: course, distanceNm: speed * self.leadTime / 1852.0)
        // normalise to -180...180 across the antimeridian
        let longitude = (lead.longitude + 540.0).truncatingRemainder(dividingBy: 360.0) - 180.0
        return CLLocationCoordinate2D(latitude: lead.latitude, longitude: longitude)
    }

    static func == (lhs : OwnshipVector, rhs : OwnshipVector) -> Bool {
        return lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.course == rhs.course && lhs.speed == rhs.speed && lhs.leadTime == rhs.leadTime
    }
}
