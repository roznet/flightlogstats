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
    
    let engineOn : TimeRange?
    let moving : TimeRange?
    let flying : TimeRange?
    let hobbs : TimeRange
    
    
    init( data : FlightData) throws {
        let values = data.datesDoubles(for: FlightLogFile.fields([.GndSpd,.IAS,.E1_PctPwr,.FQtyL,.FQtyR]) )

        let engineOnValues = values.dropFirst(field: FlightLogFile.field(.E1_PctPwr)) { $0 > 0.0 }?.dropLast(field: FlightLogFile.field(.E1_PctPwr)) { $0 > 0.0 }
        
        let movingValues = engineOnValues?.dropFirst(field: FlightLogFile.field(.GndSpd)) { $0 > 0.0 }?.dropLast(field: FlightLogFile.field(.GndSpd)) { $0 > 0.0 }
        let flyingValues = engineOnValues?.dropFirst(field: FlightLogFile.field(.IAS)) { $0 > 35.0 }?.dropLast(field: FlightLogFile.field(.IAS)) { $0 > 35.0 }
        
        
        guard let start = data.dates.first, let end = data.dates.last else {
            throw FlightSummaryError.noData
        }
        
        self.hobbs = TimeRange(start: start, end: end)

        self.engineOn = TimeRange(valuesByField: engineOnValues, field: .GndSpd)
        self.moving = TimeRange(valuesByField: movingValues, field: .GndSpd)
        self.flying = TimeRange(valuesByField: flyingValues, field: .IAS)

        guard  let fuel_start_l = values.first(field: FlightLogFile.field(.FQtyL))?.value,
               let fuel_start_r = values.first(field: FlightLogFile.field(.FQtyR))?.value,
               let fuel_end_l = values.last(field: FlightLogFile.field(.FQtyL))?.value,
               let fuel_end_r = values.last(field: FlightLogFile.field(.FQtyR))?.value
        else  {
            throw FlightSummaryError.missingFuel
        }
        
        self.fuelStart = FuelQuantity(left: fuel_start_l, right: fuel_start_r)
        self.fuelEnd = FuelQuantity(left: fuel_end_l, right: fuel_end_r)
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
