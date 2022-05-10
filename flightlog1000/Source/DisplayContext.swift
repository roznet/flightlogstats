//
//  DisplayContext.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 08/05/2022.
//

import Foundation
import CoreLocation

struct DisplayContext {
    enum UnitSystem {
        case metric
        case imperial
    }
    
    enum Style {
        case value
        case range
    }
    
    var unitSystem : UnitSystem = .metric
    var style : Style = .value
        

    //MARK: - format model objets
    func formatDecimal(timeRange : TimeRange) -> String {
        return String(format: "%.1f", timeRange.elapsed / 3600.0 )
    }
    
    func formatHHMM(timeRange : TimeRange) -> String {
        let hours = round(timeRange.elapsed / 3600.0)
        let minutes = round((timeRange.elapsed - (hours * 3600.0))/60.0)
        return String(format: "%02.0f:%02.0f", hours,minutes )
    }
    
    func format(route : [Waypoint] ) -> String {
        return route.map { $0.name }.joined(separator: ",")
    }
    
    //MARK: - format values
    func formatValue(distanceMeter : CLLocationDistance) -> String {
        return String(format: "%.1f nm", distanceMeter / 1852.0)
    }

    func formatValue(gallon : Double) -> String {
        return String(format: "%.1f gal", gallon)
    }
    
    //MARK: - format stats
    func formatStats(baro inch : ValueStats) -> String {
        switch unitSystem {
        case .metric:
            return String(format: "%.0f", inch.average)
        case .imperial:
            return String(format: "%.0f", inch.average)
        }
    }

    func formatStats(fpm : ValueStats) -> String {
        return String(format: "%.0f fpm", fpm.average)
    }

    func formatStats(degree : ValueStats) -> String {
        return String(format: "%.0f deg", degree.average)
    }
    
    func formatStats(gallon : ValueStats) -> String {
        return String(format: "%.1f gal", gallon.max-gallon.min)
    }
    
    func formatStats(distance: ValueStats) -> String {
        return String(format: "%.1f - %.1f", distance.min,distance.max)
    }
    
    
    func formatStats(engineTemp : ValueStats) -> String {
        return String(format: "%.0f - %.0f", engineTemp.min,engineTemp.max)
    }
    func formatStats(map: ValueStats) -> String {
        return String(format: "%.2f", map.average)
    }
    func formatStats(gph : ValueStats) -> String {
        return String(format: "%.1f - %.1f gph", gph.min, gph.max)
    }
    func formatStats(speed : ValueStats) -> String {
        return String(format: "%.0f kt", speed.average)
    }
    func formatStats(altitude : ValueStats) -> String {
         return String(format: "%.0f ft", altitude.average)
    }
    func formatStats(percent : ValueStats) -> String {
        return String(format: "%.0f %", percent.average * 100.0)
    }

    func formatStats(frequency : ValueStats) -> String {
        return String(format: "%@", frequency.end)
    }
    // default
    func formatStats(_ stat : ValueStats) -> String {
        return String(format: "%.0f", stat.average)
    }
    func formatStats1(_ stat : ValueStats) -> String {
        return String(format: "%.1f", stat.average)
    }

}


