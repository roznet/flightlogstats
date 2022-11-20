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
        let defs : [Field:[GroupByType]] = [.Distance:[.total],
                                            .E1_EGT_Max:[.max,.min],
                                            .FTotalizerT:[.total]]
        
        // categories by most frequency
        //  .E1_EGT_MaxIdx (int)
        //  .FltPhase (str)
        // need at least one date
        guard var currentGroupDate = data.dates.first?.roundedToNearest(interval: interval) else { return IndexedValuesByField<Date,Double,GroupByField>(fields: []) }
                
        // no fields initially build dynamically later
        var rv : IndexedValuesByField<Date,Double,GroupByField> = IndexedValuesByField<Date,Double,GroupByField>(fields: [])
        
        var doublesCollected : [Field:ValueStats] = [:]
        var started : Bool = false
        for (dateIdx,date) in data.dates.enumerated() {
            let groupDateAtIdx = date.roundedToNearest(interval: interval)
            
            if started && !groupDateAtIdx.withinOneSecond(of: currentGroupDate) {
                // collect
                for field in data.doubleFields {
                    var add : [GroupByField:Double] = [:]
                    if let def = defs[field] {
                        for type in def {
                            let groupField = GroupByField(field: field, groupedBy: type)
                            let element = doublesCollected[field]?.value(for: type) ?? .nan
                            add[groupField] = element
                        }
                    }
                    do {
                        try rv.append(fieldsValues: add, for: currentGroupDate)
                    }catch{
                        throw error
                    }
                }
                
                // Reset for next group
                currentGroupDate = groupDateAtIdx
                doublesCollected = [:]
            }
            started = true
            let valuesAtIdx = data.values[dateIdx]
            //let stringsAtIdx = strings[dateIdx]
            
            for (colIdx,field) in data.doubleFields.enumerated() {
                let value = valuesAtIdx[colIdx]
                if defs[field] != nil {
                    if doublesCollected[field] == nil {
                        let collected = GroupedValueCollected(value:value)
                        doublesCollected[field] = collected
                    }else{
                        doublesCollected[field]?.update(double: value)
                    }
                }
            }
        }
        
        return rv
    }
}
