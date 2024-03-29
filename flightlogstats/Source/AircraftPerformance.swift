//
//  Aircraft.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 23/06/2022.
//

import Foundation
import RZUtils

extension TimeInterval {
    var measurement : Measurement<Dimension> { return Measurement<Dimension>(value: self, unit: UnitDuration.seconds) }
}

struct AircraftPerformance : Equatable {
    typealias Endurance = TimeInterval
    
    let fuelMax : FuelQuantity
    let fuelTab : FuelQuantity
    
    let gph : Double
        
    init(fuelMax: FuelQuantity, fuelTab: FuelQuantity, gph: Double) {
        self.fuelMax = fuelMax
        self.fuelTab = fuelTab
        self.gph = gph
    }
    
    func endurance(fuel : FuelQuantity) -> Endurance {
        let inGallon = fuel.converted(to: UnitVolume.aviationGallon)
        return (inGallon.total / gph) * 3600.0
    }
    
    static func ==(lhs: AircraftPerformance, rhs: AircraftPerformance) -> Bool {
        return lhs.fuelMax == rhs.fuelMax && lhs.fuelTab == rhs.fuelTab && lhs.gph == rhs.gph
    }
    
    @inlinable
    public func isAlmostEqual(
      to other: Self,
      tolerance: Double = Double.ulpOfOne.squareRoot()
    ) -> Bool {
        return self.fuelMax.isAlmostEqual(to: other.fuelMax) && self.fuelTab.isAlmostEqual(to: other.fuelTab) && self.gph.isAlmostEqual(to: other.gph)
    }
}
