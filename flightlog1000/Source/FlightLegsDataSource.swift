//
//  FlightLegsDataSource.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 11/05/2022.
//

import Foundation
import UIKit
import OSLog
import RZUtils
import RZUtilsSwift

class FlightLegsDataSource : TableDataSource {
        
    typealias Field = FlightLogFile.Field
    typealias LegInfo = FlightLeg.LegInfo
    
    let legs : [FlightLeg]
    let fields : [Field]
    let fixedColumnsInfo : [LegInfo]
    let displayContext : DisplayContext
    
    init(legs : [FlightLeg], displayContext : DisplayContext = DisplayContext()){
        self.legs = legs
        
        var fields : Set<Field> = []
        for leg in legs {
            fields.formUnion(leg.fields)
        }
        self.fields = Array(fields).sorted {
            $0.order < $1.order
        }

        // should be sorted
        self.displayContext = displayContext
        self.fixedColumnsInfo = [.end_time,.waypoint]
        
        super.init(rows: self.legs.count+1,
                   columns: self.fixedColumnsInfo.count + self.fields.count,
                   frozenColumns: self.fixedColumnsInfo.count,
                   frozenRows: 1)
        
    }
    
    //MARK: - delegate
        
    var titleAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.boldSystemFont(ofSize: 14.0)]
    var cellAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize: 14.0)]
    
    func formattedValueFor(field : Field, row : Int) -> GCNumberWithUnit? {
        guard let leg = self.legs[safe: row],
              let value = leg.valueStats(field: field)
        else {
            // empty string if missing for a blank in the table
            return nil
        }
        
        return field.numberWithUnit(valueStats: value, context: self.displayContext)
    }
    
    // helpers:
    
    func field(at indexPath: IndexPath) -> Field? {
        let fieldIdx = indexPath.item - self.fixedColumnsInfo.count
        if self.fields.indices.contains(fieldIdx) {
            return self.fields[fieldIdx]
        }
        return nil
    }
    
    func leg(at indexPath : IndexPath) -> FlightLeg? {
        let legIdx = indexPath.section - 1
        if self.legs.indices.contains(legIdx) {
            return self.legs[legIdx]
        }
        return nil
    }
    
    override func prepare() {
        self.cellHolders  = []
        self.geometries   = []
        
        self.cellAttributes = ViewConfig.shared.cellAttributes
        self.titleAttributes = ViewConfig.shared.titleAttributes
        self.frozenColor = UIColor.systemBrown

        if let first = legs.first {
            // col 0 = time since start
            // col 1 = leg waypoints

            let reference = first.timeRange.start
            
            // first headers
            for title in self.fixedColumnsInfo {
                let titleAttributed = CellHolder(string: title.description, attributes: self.titleAttributes)
                self.cellHolders.append(titleAttributed)
                self.geometries.append(RZNumberWithUnitGeometry())
            }

            for field in fields {
                let fieldAttributed = CellHolder(string: field.description, attributes: self.titleAttributes)
                self.cellHolders.append(fieldAttributed)
                let geometry = RZNumberWithUnitGeometry()
                geometry.defaultUnitAttribute = self.cellAttributes
                geometry.defaultNumberAttribute = self.cellAttributes
                geometry.numberAlignment = .decimalSeparator
                geometry.unitAlignment = .left
                geometry.alignment = .center
                self.geometries.append(geometry)
            }
            
            
            for (row,leg) in legs.enumerated() {
                for info in self.fixedColumnsInfo {
                    let fixedAttributed = CellHolder(string: leg.format(which: info, displayContext: self.displayContext, reference: reference), attributes: self.titleAttributes)
                    self.cellHolders.append(fixedAttributed)
                }
                var geoIndex = self.fixedColumnsInfo.count
                for field in fields {
                    if let nu = self.formattedValueFor(field: field, row: row) {
                        self.geometries[geoIndex].adjust(for: nu)
                        self.cellHolders.append(CellHolder.numberWithUnit(nu))
                    }else{
                        self.cellHolders.append(CellHolder(string: "", attributes: self.cellAttributes))
                    }
                    geoIndex += 1
                }
            }
        }
    }
}
