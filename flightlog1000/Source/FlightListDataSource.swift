//
//  FlightListDataSource.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 24/07/2022.
//

import UIKit
import OSLog
import RZUtils
import RZUtilsSwift

class FlightListDataSource: TableDataSource  {
    
    var logInfos : [FlightLogFileInfo]
    var logFileOrganizer = FlightLogOrganizer.shared
    
    let displayContext : DisplayContext
    
    let fields : [FlightSummary.Field]
    let headers : [String]
    
    //               Total    Left   Right
    //    Start
    //    End
    //    Remaining
    
    init(displayContext : DisplayContext = DisplayContext()){
        self.fields = [.Hobbs, .Moving, .Flying, .FuelStart, .FuelEnd, .FuelUsed, .FuelTotalizer, .GpH, .NmpG, .Distance, .GroundSpeed]
        self.headers = [ "Date", "From", "To", "Start", "End"]
        self.logInfos = self.logFileOrganizer.actualFlightLogFileInfos
        self.displayContext = displayContext

        super.init(rows: self.logInfos.count, columns: self.fields.count + self.headers.count, frozenColumns: 1, frozenRows: 1)
    }
    
    //MARK: - delegate

    override func prepare() {
        
        self.cellHolders  = []
        self.geometries = []
        
        let titleAttributes : [NSAttributedString.Key:Any] = ViewConfig.shared.titleAttributes
        let cellAttributes : [NSAttributedString.Key:Any] = ViewConfig.shared.cellAttributes
        
        for title in headers {
            let geometry = RZNumberWithUnitGeometry()
            geometry.defaultUnitAttribute = cellAttributes
            geometry.defaultNumberAttribute = cellAttributes
            geometry.numberAlignment = .right
            geometry.unitAlignment = .left
            geometry.alignment = .center
            self.geometries.append(geometry)
            self.cellHolders.append(CellHolder(string: title, attributes: titleAttributes))
        }
        
        for field in fields {
            let geometry = RZNumberWithUnitGeometry()
            geometry.defaultUnitAttribute = cellAttributes
            geometry.defaultNumberAttribute = cellAttributes
            geometry.numberAlignment = .right
            geometry.unitAlignment = .left
            geometry.alignment = .left
            self.geometries.append(geometry)
            self.cellHolders.append(CellHolder(string: field.rawValue, attributes: titleAttributes))
        }
        
        for info in self.logInfos {
            if let summary = info.flightSummary, let hobbs = summary.hobbs {
                self.cellHolders.append(CellHolder(string:  self.displayContext.format(date: hobbs.start), attributes: titleAttributes))
                self.cellHolders.append(CellHolder(string:  self.displayContext.format(airport: summary.startAirport, style: .icaoOnly), attributes: titleAttributes))
                self.cellHolders.append(CellHolder(string:  self.displayContext.format(airport: summary.endAirport, style: .icaoOnly), attributes: titleAttributes))
                self.cellHolders.append(CellHolder(string:  self.displayContext.format(time: hobbs.start), attributes: cellAttributes))
                self.cellHolders.append(CellHolder(string:  self.displayContext.format(time: hobbs.end), attributes: cellAttributes))
                var geoIndex = self.headers.count
                for field in fields {
                    if let nu = summary.numberWithUnit(for: field) {
                        geometries[geoIndex].adjust(for: nu)
                        self.cellHolders.append(CellHolder.numberWithUnit(nu))
                    }else{
                        self.cellHolders.append(CellHolder(string: "", attributes: cellAttributes))
                    }
                    geoIndex += 1
                }
            }else{
                print( "Why?")
            }
        }
    }
}
