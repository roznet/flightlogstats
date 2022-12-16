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
import OSLog

class Trips {
    
    enum Aggregation {
        case trips
        case months
    }
    private let flightFileInfos : [FlightLogFileInfo]
    
    private(set) var base : Airport? = nil
    private(set) var airportVisits : [Airport:[Visit]] = [:]
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
    
    func countAircrafts(message: String, infos : [FlightLogFileInfo]) {
        var systems : [String:Int] = [:]
        for info in infos {
            let systemId = info.system_id ?? "Null"
            systems[systemId, default: 0] += 1
        }
        Logger.app.info( "\(message) \(systems)" )
    }
    
    func computeTrips(first : Trip) {
        var trips : [Trip] = []
        var trip : Trip = first
        
        // go from first to last trip
        var infos = self.flightFileInfos.sorted { $0.isOlder(than: $1) }
        
        var countGuard : Int = self.flightFileInfos.count + 1
        
        while countGuard > 0 && infos.count > 0 {
            self.countAircrafts(message: "trip start", infos: infos)
            countGuard -= 1
            var leftOver : [FlightLogFileInfo] = []
            let aircraftCheck = infos.first
            for info in infos {
                switch trip.check(info: info, sample: aircraftCheck) {
                case .endsTrip:
                    trip.add(info: info)
                    trips.append(trip)
                    Logger.app.info("Ended trip : \(trip.description)")
                    if let next = trip.new(info: info) {
                        trip = next
                    }else{
                        break
                    }
                case .startsTrip:
                    trips.append(trip)
                    Logger.app.info("Ended trip : \(trip.description)")
                    if let next = trip.new(info: info) {
                        trip = next
                        trip.add(info: info)
                    }else{
                        break
                    }
                case .sameTrip:
                    trip.add(info: info)
                case .ignore:
                    leftOver.append(info)
                    break
                }
            }
            if !trip.empty {
                Logger.app.info("Ended trip : \(trip.description)")
                trips.append(trip)
                if let next = trip.new(){
                    trip = next
                }                
            }
            infos = leftOver.sorted { $0.isOlder(than: $1) }
        }
        if countGuard == 0 {
            Logger.app.error("infinite loop guard hit")
        }
        trips.sort { $0.isNewer(than: $1)}
        
        self.trips = trips
    }
    
    func computeVisits() {
        var rv : [Airport:[Visit]] = [:]
        
        var currentVisit : Visit? = nil
        for info in self.flightFileInfos.reversed() {
            if let summary = info.flightSummary,
               let startAirport = summary.startAirport,
               let endAirport = summary.endAirport{
                // ignore local flights
                if startAirport == endAirport {
                    continue
                }
                if var currentVisit = currentVisit {
                    currentVisit.departed(with: info)
                    if rv[startAirport] == nil {
                        rv[startAirport] = [currentVisit]
                    }else{
                        rv[startAirport]?.append(currentVisit)
                    }
                }
                currentVisit = Visit(airport: endAirport, arrivingFlight: info)
            }
        }
        
        var baseFound : Airport? = nil
        var baseNights : Int = 0
        
        for (airport,visits) in rv {
            let nights = visits.reduce(0) {
                cnt,visit in
                let days = visit.numberOfDays
                return cnt + days
            }
            if nights > baseNights {
                baseFound = airport
                baseNights = nights
            }
        }
        if let baseFound = baseFound {
            self.base = baseFound
        }

        self.airportVisits = rv
    }
    func computeVisitsSimple() -> [Airport:[Int]]{
        // 7/23 egmd - egtf
        // 7/23 egtf - egmd
        // 7/21 lfaq - egtf
        // 7/15 egtf - lfaq
        // 7/10 egtf - egtf
        
        var rv : [Airport:[Int]] = [:]
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
                        if rv[endAirport] == nil {
                            rv[endAirport] = [days]
                        }else{
                            rv[endAirport]?.append(days)
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
        
        for (airport,days) in rv {
            let nights = days.reduce(0, +)
            if nights > baseNights {
                baseFound = airport
                baseNights = nights
            }
        }
        if let baseFound = baseFound {
            self.base = baseFound
        }
        return rv
    }
}
