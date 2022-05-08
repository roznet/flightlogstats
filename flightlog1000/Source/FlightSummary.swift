//
//  FlightSummary.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 07/05/2022.
//

import Foundation


struct FlightSummary {
    enum FlightSummaryError : Error {
        case noData
        case missingFuel
    }
    
    let fuelStart : FuelQuantity
    let fuelEnd : FuelQuantity
    var fuelUsed : FuelQuantity { return self.fuelStart - self.fuelEnd }
    
    private let engineOn : TimeRange?
    let moving : TimeRange?
    let flying : TimeRange?
    let hobbs : TimeRange
    
    let route : [Waypoint]
    
    init?( info : FlightLogFileInfo ) {
        guard let start = info.start_time_moving, let end = info.end_time else { return nil }
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
        }else{
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
    }
    
    init( data : FlightData) throws {
        let values = data.datesDoubles(for: [.GndSpd,.IAS,.E1_PctPwr,.FQtyL,.FQtyR] )

        let engineOnValues = values.dropFirst(field: .E1_PctPwr) { $0 > 0.0 }?.dropLast(field: .E1_PctPwr) { $0 > 0.0 }
        
        let movingValues = engineOnValues?.dropFirst(field: .GndSpd) { $0 > 0.0 }?.dropLast(field: .GndSpd) { $0 > 0.0 }
        let flyingValues = engineOnValues?.dropFirst(field: .IAS) { $0 > 35.0 }?.dropLast(field: .IAS) { $0 > 35.0 }
        
        
        guard let start = data.dates.first, let end = data.dates.last else {
            throw FlightSummaryError.noData
        }
        
        self.hobbs = TimeRange(start: start, end: end)

        self.engineOn = TimeRange(valuesByField: engineOnValues, field: .GndSpd)
        self.moving = TimeRange(valuesByField: movingValues, field: .GndSpd)
        self.flying = TimeRange(valuesByField: flyingValues, field: .IAS)

        guard  let fuel_start_l = values.first(field: .FQtyL)?.value,
               let fuel_start_r = values.first(field: .FQtyR)?.value,
               let fuel_end_l = values.last(field: .FQtyL)?.value,
               let fuel_end_r = values.last(field: .FQtyR)?.value
        else  {
            throw FlightSummaryError.missingFuel
        }
        
        self.fuelStart = FuelQuantity(left: fuel_start_l, right: fuel_start_r)
        self.fuelEnd = FuelQuantity(left: fuel_end_l, right: fuel_end_r)
        
        let identifiers = data.datesStrings(for: [.AtvWpt])
        if let names = identifiers[.AtvWpt]?.values {
            self.route = names.compactMap {
                return Waypoint(name: $0)
            }
        }else{
            self.route = []
        }
    }
}

extension FlightSummary : CustomStringConvertible {
    var description: String {
        if let flying = self.flying {
            return "<FlightSummary: hobbs:\(self.hobbs.elapsedAsDecimalHours) flying:\(flying.elapsedAsDecimalHours) fuel:\(self.fuelUsed.totalAsGallon)>"
        }else{
            return "<FlightSummary: hobbs:\(self.hobbs.elapsedAsDecimalHours) fuel:\(self.fuelUsed.totalAsGallon)>"
        }
    }
}
