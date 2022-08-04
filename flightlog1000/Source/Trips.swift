//
//  Trips.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 31/07/2022.
//

import Foundation
import RZFlight
import RZUtils

extension Calendar {
    func numberOfNights(from : Date, to: Date) -> Int {
        let fromStart = self.startOfDay(for: from)
        let toStart = self.startOfDay(for: to)
        
        let rv = dateComponents([.day], from: fromStart, to: toStart)
        
        return rv.day!
    }
}

extension Airport : CustomStringConvertible {
    public var description : String { return "\(icao)" }
}
class Trips {
    private let flightFileInfos : [FlightLogFileInfo]
    
    private(set) var base : Airport? = nil
    private(set) var airportVisits : [Airport:[Int]] = [:]
    private(set) var trips : [Trip] = []
    
    init(infos : [FlightLogFileInfo]){
        self.flightFileInfos = infos
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
        self.computeTrips()
    }
    
    func computeTrips() {
        var trips : [ Trip ] = []
        
        if let base = self.base {
            var trip : Trip = Trip(base: base)

            for info in self.flightFileInfos {
                if trip.add(info: info) {
                    trips.append(trip)
                    trip = Trip(base: base)
                }
            }
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
        
        let check = "LFMD"
        
        for info in self.flightFileInfos {
            if let summary = info.flightSummary,
               let startAirport = summary.startAirport,
               let endAirport = summary.endAirport,
               let hobbs = summary.hobbs
            {
                if endAirport == startAirport {
                    continue
                }
                
                if endAirport.icao == check || startAirport.icao == check {
                    print( "\(hobbs.start): \(startAirport.icao)-\(endAirport.icao)")
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
            let count = days.count
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
