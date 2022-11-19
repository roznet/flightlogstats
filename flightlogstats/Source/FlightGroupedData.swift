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
    
    enum GroupByType {
        case start,end
        case min,max,avg
        case total
        // Discrete
        //case maxfreq,minIdx,maxIdx
    }
    
    struct GroupByField {
        let field : Field
        let groupedBy : GroupByType
    }
    
    struct GroupedValueCollected {
        let start : Double
        var end : Double
        var min : Double
        var max : Double
        var sum : Double
        var cnt : Double
        var avg : Double { return sum/cnt }
        var total : Double { return end - start }
        
        init(_ val : Double) {
            start = val
            end = val
            min = val
            max = val
            sum = val
            cnt = 1.0
        }
        
        mutating func add(_ val : Double){
            end = val
            min = Swift.min(val,min)
            max = Swift.max(val,max)
            sum += val
            cnt += 1.0
        }
        
        func value(type: GroupByType) -> Double{
            switch type {
            case .max:
                return self.max
            case .avg:
                return self.avg
            case .min:
                return self.min
            case .end:
                return self.end
            case .start:
                return self.start
            case .total:
                return self.total
            }

        }
    }
    
    func groupBy(data : FlightData, interval : TimeInterval) {
        let defs : [Field:[GroupByType]] = [.Distance:[.total],
                                            .E1_EGT_Max:[.max,.min],
                                            .FTotalizerT:[.total]]
        
        // categories by most frequency
        //  .E1_EGT_MaxIdx (int)
        //  .FltPhase (str)
        
        // need at least one date
        guard var currentGroupDate = data.dates.first?.roundedToNearest(interval: interval) else { return }
        
        var datesGrouped : [Date] = []
        var doublesGroupedValues : [[Double]] = []
        var doublesGroupedFields : [GroupByField] = []
        
        var doublesCollected : [Field:GroupedValueCollected] = [:]
        var started : Bool = false
        for (dateIdx,date) in data.dates.enumerated() {
            
            let groupDateAtIdx = date.roundedToNearest(interval: interval)
            
            if started && !groupDateAtIdx.withinOneSecond(of: currentGroupDate) {
                // collect
                var groupedIdx = 0
                var line : [Double] = []
                for field in data.doubleFields {
                    if let def = defs[field] {
                        for type in def {
                            if groupedIdx == doublesGroupedFields.count  {
                                doublesGroupedFields.append(GroupByField(field: field, groupedBy: type))
                            }
                            line.append(doublesCollected[field]?.value(type: type) ?? .nan)
                            groupedIdx += 1
                        }
                    }
                }
                doublesGroupedValues.append(line)
                datesGrouped.append(currentGroupDate)
                
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
                        let collected = GroupedValueCollected(value)
                        doublesCollected[field] = collected
                    }else{
                        doublesCollected[field]?.add(value)
                    }
                }
            }
        }
        print( doublesGroupedValues.count)
    }
}
