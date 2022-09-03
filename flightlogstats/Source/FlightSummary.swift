//
//  FlightSummary.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 07/05/2022.
//

import Foundation
import CoreLocation
import RZFlight
import RZUtils
import OSLog

struct FlightSummary : Codable {
    enum FlightSummaryError : Error {
        case noData
        case missingFuel
    }
    
    enum SummaryType : String, Codable {
        case empty
        case preflight
        case ground
        case flight
    }
    
    let summaryType : SummaryType
    
    let fuelStart : FuelQuantity
    let fuelEnd : FuelQuantity
    var fuelUsed : FuelQuantity { return self.fuelStart - self.fuelEnd }
    var fuelTotalizer : FuelQuantity
    
    let engineOn : TimeRange?
    let moving : TimeRange?
    let flying : TimeRange?
    let hobbs : TimeRange?
    
    let route : [Waypoint]
    
    var startAirport : Airport? = nil
    var endAirport : Airport? = nil
    
    /// in nm
    let distanceInNm : Double
    let altitudeInFeet : Double
    
    init?( info : FlightLogFileInfo ) {
        guard let start = info.start_time_moving, let end = info.end_time else {
            return nil
        }
        
        self.hobbs = TimeRange(start: start, end: end)
        if let start_moving = info.start_time_moving,
           let end_moving = info.end_time_moving {
            self.moving = TimeRange(start: start_moving, end: end_moving)
            
        }else{
            self.moving = nil
        }
        if let start_flying = info.start_time_flying,
           let end_flying = info.end_time_flying {
            self.flying = TimeRange(start: start_flying, end: end_flying)
            self.summaryType = .flight
        }else{
            if self.moving != nil {
                self.summaryType = .ground
            }else{
                self.summaryType = .preflight
            }
            self.flying = nil
        }
        if let route = info.route, route.count > 0 {
            self.route = route.components(separatedBy: ",").compactMap { Waypoint(name: $0) }
        }else{
            self.route = []
        }
        self.engineOn = nil
        
        self.fuelStart = FuelQuantity(left: info.start_fuel_quantity_left, right: info.start_fuel_quantity_right)
        self.fuelEnd = FuelQuantity(left: info.end_fuel_quantity_left, right: info.end_fuel_quantity_right)
        self.fuelTotalizer = FuelQuantity(total: info.fuel_totalizer_total)
        
        self.distanceInNm = info.total_distance
        self.altitudeInFeet = info.max_altitude
        
        if let start_airport_icao = info.start_airport_icao {
            self.startAirport = try? Airport(db: AppDelegate.db, ident: start_airport_icao)
        }
        if let end_airport_icao = info.end_airport_icao {
            self.endAirport = try? Airport(db: AppDelegate.db, ident: end_airport_icao)
        }
    }
    
    init( data : FlightData) throws {
        let values = data.datesDoubles(for: [.GndSpd,.IAS,.E1_PctPwr,.FQtyL,.FQtyR,.Distance,.FTotalizerT,.AltInd] )
        
        let engineOnValues = values.dropFirst(field: .E1_PctPwr) { $0 > 0.0 }?.dropLast(field: .E1_PctPwr) { $0 > 0.0 }
        let movingValues = engineOnValues?.dropFirst(field: .GndSpd, minimumMatchCount: 5) { $0 > 0.0 }?.dropLast(field: .GndSpd) { $0 > 0.0 }
        let flyingValues = engineOnValues?.dropFirst(field: .IAS) { $0 > 35.0 }?.dropLast(field: .IAS) { $0 > 35.0 }

        guard let start = data.dates.first, let end = data.dates.last else {
            self.summaryType = .empty
            self.engineOn = nil
            self.moving = nil
            self.flying = nil
            self.hobbs = nil
            
            self.fuelEnd = FuelQuantity.zero
            self.fuelStart = FuelQuantity.zero
            self.fuelTotalizer = FuelQuantity.zero
            self.distanceInNm = 0.0
            self.altitudeInFeet = 0.0
            self.route = []
            return
        }
        
        self.hobbs = TimeRange(start: start, end: end)

        self.engineOn = TimeRange(valuesByField: engineOnValues, field: .GndSpd)
        self.moving = TimeRange(valuesByField: movingValues, field: .GndSpd)
        self.flying = TimeRange(valuesByField: flyingValues, field: .IAS)

        if engineOn == nil {
            self.summaryType = .preflight
        }else{
            if moving == nil {
                self.summaryType = .preflight
            }else{
                if flying == nil {
                    self.summaryType = .ground
                }else{
                    self.summaryType = .flight
                }
            }
        }
        let fuel_start_l = values.first(field: .FQtyL)?.value ?? 0.0
        let fuel_start_r = values.first(field: .FQtyR)?.value ?? 0.0
        let fuel_end_l = values.last(field: .FQtyL)?.value ?? 0.0
        let fuel_end_r = values.last(field: .FQtyR)?.value ?? 0.0
        let fuel_totalizer = values.last(field: .FTotalizerT)?.value ?? 0.0
        
        self.fuelStart = FuelQuantity(left: fuel_start_l, right: fuel_start_r)
        self.fuelEnd = FuelQuantity(left: fuel_end_l, right: fuel_end_r)
        self.fuelTotalizer = FuelQuantity(total: fuel_totalizer)
        
        self.distanceInNm = values.last(field: .Distance)?.value ?? 0.0
        self.altitudeInFeet = values.max(for: .AltInd) ?? 0.0

        let identifiers = data.datesStrings(for: [.AtvWpt])

        if let names = identifiers[.AtvWpt]?.values {
            self.route = names.compactMap {
                return Waypoint(name: $0)
            }
        }else{
            self.route = []
        }
        
        self.startAirport = AppDelegate.knownAirports?.nearest(coord: data.firstCoordinate, db: AppDelegate.db)
        self.endAirport = AppDelegate.knownAirports?.nearest(coord: data.lastCoordinate, db: AppDelegate.db)

    }
    
    func contains(_ searchText : String) -> Bool {
        if (self.startAirport?.contains(searchText) ?? false) || (self.endAirport?.contains(searchText) ?? false) {
            return true
        }
        return false
    }
    
}

extension FlightSummary : CustomStringConvertible {
    
    var routeSummary : String? {
        var strs : [String] = []
        if let startAirport = self.startAirport {
            strs.append(startAirport.icao)
        }
        if let endAirport = self.endAirport {
            strs.append(endAirport.icao)
        }
        return strs.count > 0 ? strs.joined(separator: "-") : nil
    }
    
    var description: String {
        var strs : [String] = []
        if let route = self.routeSummary {
            strs.append(route)
        }
        
        let fields : [Field] = [ .Hobbs, .Distance, .FuelTotalizer]
        for field in fields {
            if let nu = self.numberWithUnit(for: field) {
                strs.append(nu.formatDouble())
            }
        }
        if strs.count > 0 {
            let desc = strs.joined(separator: ", ")
            return "FlightSummary(\(desc)"
        }else{
            return "FlightSummary(empty)"
        }
    }
}
