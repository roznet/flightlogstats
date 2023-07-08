//
//  FlightSummaryFuelDataSource.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 12/06/2022.
//

import UIKit
import OSLog
import RZUtils
import RZUtilsSwift

class FlightSummaryFuelDataSource: TableDataSource {

    let flightSummary : FlightSummary
    let displayContext : DisplayContext
    
    //               Total    Left   Right
    //    Start
    //    End
    //    Remaining
    
    init(flightSummary : FlightSummary, displayContext : DisplayContext = DisplayContext()){
        self.flightSummary = flightSummary
        self.displayContext = displayContext
        super.init(rows: 4, columns: 5, frozenColumns: 1, frozenRows: 1)
    }
    
    //MARK: - delegate
        
    var titleAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.boldSystemFont(ofSize: 14.0)]
    var cellAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize: 14.0)]
    
    override func prepare() {
        
        self.cellHolders  = []
        self.geometries = []
        
        self.cellAttributes = ViewConfig.shared.cellAttributes
        self.titleAttributes = ViewConfig.shared.titleAttributes
        
        for title in [ "Fuel", "Total", "Left", "Right", "Totalizer" ] {
            self.cellHolders.append(CellHolder(string: title, attributes: self.titleAttributes))
            let geometry = RZNumberWithUnitGeometry()
            geometry.defaultUnitAttribute = self.cellAttributes
            geometry.defaultNumberAttribute = self.cellAttributes
            geometry.numberAlignment = .decimalSeparator
            geometry.unitAlignment = .left
            geometry.alignment = .center
            self.geometries.append(geometry)
        }
        
        for (name,fuel,totalizer) in [("Start", self.flightSummary.fuelStart,self.flightSummary.fuelStart),
                                      ("End", self.flightSummary.fuelEnd,self.flightSummary.fuelStart-self.flightSummary.fuelTotalizer),
                                      ("Used", self.flightSummary.fuelUsed,self.flightSummary.fuelTotalizer)
        ] {
            self.cellHolders.append(CellHolder(string: name, attributes: self.titleAttributes))
            var geoIndex = 1
            var attr : [NSAttributedString.Key:Any]? = nil
            if !self.flightSummary.totaliserConsistent {
                attr = self.cellAttributes
                attr![.backgroundColor] = UIColor.yellow
            }
            for (fuelVal,a) in [(fuel.totalMeasurement,attr), (fuel.leftMeasurement,nil), (fuel.rightMeasurement,nil), (totalizer.totalMeasurement,attr)] {
                if fuelVal.value != 0.0 {
                    let measurement = fuelVal.measurementDimension
                    // pick one fuel field, should be all the same
                    let dv = self.displayContext.displayedValue(field: .FQtyT, measurement: measurement)
                    dv.adjust(geometry: self.geometries[geoIndex])
                    self.cellHolders.append(dv.cellHolder(attributes: a))
                }else{
                    self.cellHolders.append(CellHolder(string: "", attributes: self.cellAttributes))
                }
                geoIndex += 1
            }
        }
    }
}
