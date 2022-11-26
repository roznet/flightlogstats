//
//  FlightData+Summarized.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 19/11/2022.
//

import Foundation
/*
 * Stats
 *   per minute:
 *      time start
 *      distance total
 *      long/lat start
 
 *      engine on/off maxfreq
 *      phase climb/descent/cruise/ground maxfreq
 
 *      AltMSL min/max/start/end
 *      AltGPS min/max/start/end
 
 *      fuel used  total
 *      fuel       imbalance
 
 *      TAS/IAS/GS  min/max/avg
 *      fuel flow  min/max/avg
 *      OilT/OilP avg
 *      MAP max/min/avg
 *      RPM max/min/avg
 *      %pwd max/min/avg
 *      OAT min/max/avg
 *      volt1/2  start/end/avg
 *      amp      start/end/avg
 
 *      CHTn max/min/median/maxI,minI
 *      EGTn max/min/median/maxI,minI
 *      TITn max/min/median/maxI,minI
 
 * calc type:
 *    start/end: first value, last value
 *    min/max/avg/minI/maxI/median
 *    total: last value - first value
 *    maxfreq: value most frequent
 
 */

extension Date {
    func roundedToNearest(interval : TimeInterval) -> Date {
        return Date(timeIntervalSinceReferenceDate: round(self.timeIntervalSinceReferenceDate/interval) * interval )
    }
    
    func withinOneSecond(of : Date) -> Bool {
        let diff = self.timeIntervalSinceReferenceDate - of.timeIntervalSinceReferenceDate
        return diff > -0.5 && diff < 0.5
    }
}

class FlightGroupedData  {
    typealias Field = FlightData.Field
    typealias GroupedValueCollected = ValueStats
    typealias GroupByType = ValueStats.Metric
    
    struct GroupByField : Hashable {
        let field : Field
        let groupedBy : GroupByType
    }
        
    func groupBy(data : FlightData, interval : TimeInterval) throws -> IndexedValuesByField<Date,Double,GroupByField> {
        let valuesDefs : [Field:[GroupByType]] = [.Distance:[.total],
                                            .E1_EGT_Max:[.max,.min],
                                            .FTotalizerT:[.total]]
        
        // categories by most frequency
        //  .E1_EGT_MaxIdx (int)
        //  .FltPhase (str)
        //let categoricalDefs : [Field:[]
        
        let values = data.doubleValues(for: Array(valuesDefs.keys))
        let schedule = values.indexes.regularShedule(interval: interval)
        let stats = try values.extractValueStats(indexes: schedule)
                
        // no fields initially build dynamically later
        var rv : IndexedValuesByField<Date,Double,GroupByField> = IndexedValuesByField<Date,Double,GroupByField>(fields: [])
        
        for (date,row) in stats {
            for (field,valueStat) in row {
                var add : [GroupByField:Double] = [:]
                if let def = valuesDefs[field] {
                    for type in def {
                        let groupField = GroupByField(field: field, groupedBy: type)
                        let element = valueStat.value(for: type)
                        add[groupField] = element
                    }
                }
                do {
                    try rv.append(fieldsValues: add, for: date)
                }catch{
                    throw error
                }
            }
        }
        return rv
    }
}
