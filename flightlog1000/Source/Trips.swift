//
//  Trips.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 31/07/2022.
//

import Foundation
import RZFlight
import RZUtils
import RZUtilsSwift


class Trips {
    
    enum Aggregation {
        case trips
        case months
    }
    private let flightFileInfos : [FlightLogFileInfo]
    
    private(set) var base : Airport? = nil
    private(set) var airportVisits : [Airport:[Int]] = [:]
    private(set) var trips : [Trip] = []
    
    var aggregation : Aggregation
    init(infos : [FlightLogFileInfo], aggregation : Aggregation = .trips){
        self.flightFileInfos = infos
        self.aggregation = aggregation
    }
    
    var infoCount : Int {
        return trips.reduce(0) {
            c, t in return c+t.count
        }
    }
    var tripCount : Int {
        return trips.count
    }
    
    func compute() {
        self.computeVisits()
        
        switch self.aggregation {
        case .months:
            self.computeTrips(first: Trip(unit: .month))
        case .trips:
            if let base = self.base {
                self.computeTrips(first: Trip(base: base))
            }
        }
    }
    
    func computeTrips(first : Trip) {
        var trips : [ Trip ] = []
        var trip : Trip = first
        
        for info in self.flightFileInfos {
            if trip.add(info: info) {
                trips.append(trip)
                if let next = trip.next(info: info) {
                    trip = next
                }else{
                    // no more
                    break
                }
            }
        }
        if !trip.empty {
            trips.append(trip)
        }
        
        self.trips = trips
    }
    
    func computeVisits() {
        // 7/23 egmd - egtf
        // 7/23 egtf - egmd
        // 7/21 lfaq - egtf
        // 7/15 egtf - lfaq
        // 7/10 egtf - egtf
        
        self.airportVisits = [:]
        var lastAirport : Airport? = nil
        var lastTime : Date? = nil
        
        let calendar = Calendar.current
        
        for info in self.flightFileInfos {
            if let summary = info.flightSummary,
               let startAirport = summary.startAirport,
               let endAirport = summary.endAirport,
               let hobbs = summary.hobbs
            {
                if endAirport == startAirport {
                    continue
                }
                
                if let lastTimeReported = lastTime,
                    let lastAirportReported = lastAirport {
                    let days = calendar.numberOfNights(from: hobbs.end, to: lastTimeReported)
                    if endAirport == lastAirportReported {
                        if airportVisits[endAirport] == nil {
                            airportVisits[endAirport] = [days]
                        }else{
                            airportVisits[endAirport]?.append(days)
                        }
                    }else{
                        // hum, missing a leg?
                    }
                        
                }
                lastAirport = startAirport
                lastTime = hobbs.end
            }
        }
        var baseFound : Airport? = nil
        var baseNights : Int = 0
        
        for (airport,days) in airportVisits {
            let nights = days.reduce(0, +)
            if nights > baseNights {
                baseFound = airport
                baseNights = nights
            }
        }
        if let baseFound = baseFound {
            self.base = baseFound
        }
    }
}
