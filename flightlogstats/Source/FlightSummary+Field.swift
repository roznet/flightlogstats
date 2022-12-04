//
//  FlightSummary+Field.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 24/07/2022.
//

import Foundation
import RZUtils
import RZUtilsSwift

extension FlightSummary {
    enum Field : String, CaseIterable {
        case FuelStart
        case FuelEnd
        case FuelUsed
        case FuelTotalizer
        
        case GpH
        case NmpG
        
        case Distance
        case Altitude
        case GroundSpeed
        
        case Hobbs
        case Flying
        case Moving
        
    }
    
    func measurement(for field : Field) -> Measurement<Dimension>? {
        switch field {
        case .Distance:
            return Measurement(value: self.distanceInNm, unit: UnitLength.nauticalMiles)
        case .Altitude:
            return Measurement(value: self.altitudeInFeet, unit: UnitLength.feet)
        case .GroundSpeed:
            if let flying = self.flying?.elapsed,
               let moving = self.moving?.elapsed{
                var elapsed = flying
                let nonflying = moving - flying
                if nonflying > flying {
                    elapsed = moving
                }
                return Measurement(value: self.distanceInNm/(elapsed/3600.0), unit: UnitSpeed.knots)
            }else{
                return Measurement(value: 0.0, unit: UnitSpeed.knots)
            }
        case .FuelStart:
            return self.fuelStart.totalMeasurement.measurementDimension
            
        case .FuelEnd:
            return self.fuelEnd.totalMeasurement.measurementDimension
        case .FuelUsed:
            return self.fuelUsed.totalMeasurement.measurementDimension
        case .FuelTotalizer:
            return self.fuelTotalizer.totalMeasurement.measurementDimension
            
        case .GpH:
            if let flying = self.moving?.elapsed {
                let fuelTotal = (self.fuelTotalizer.total > 0.0 ? self.fuelTotalizer.total : self.fuelUsed.total)
                return Measurement(value: fuelTotal / (flying/3600.0), unit: UnitFuelFlow.gallonPerHour)
            }else{
                return Measurement(value: 0.0, unit: UnitFuelFlow.gallonPerHour)
            }
        case .NmpG:
            if self.distanceInNm > 0.0 {
                let fuelTotal = (self.fuelTotalizer.total > 0.0 ? self.fuelTotalizer.total : self.fuelUsed.total)
                return Measurement(value: self.distanceInNm/fuelTotal, unit: UnitFuelEfficiency.nauticalMilesPerGallon)
            }else{
                return Measurement(value: 0.0, unit: UnitFuelEfficiency.nauticalMilesPerGallon)
            }
        case .Hobbs:
            return self.hobbs?.measurement.converted(to: UnitDuration.hours)
        case .Moving:
            return self.moving?.measurement.converted(to: UnitDuration.hours)
        case .Flying:
            return self.flying?.measurement.converted(to: UnitDuration.hours)
        }

    }

}
