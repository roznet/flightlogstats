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
    
    var trips : Trips
    let displayContext : DisplayContext
    
    let fields : [FlightSummary.Field]
    let headers : [String]
    
    //               Total    Left   Right
    //    Start
    //    End
    //    Remaining
    
    init(displayContext : DisplayContext = DisplayContext(), aggregation : Trips.Aggregation = .trips){
        self.fields = [.Hobbs, .Moving, .Flying, .FuelStart, .FuelEnd, .FuelUsed, .FuelTotalizer, .GpH, .NmpG, .Distance, .GroundSpeed]
        self.headers = [ "Date", "From", "To", "Start", "End"]
        self.logInfos = self.logFileOrganizer.actualFlightLogFileInfos
        self.displayContext = displayContext
        self.trips = Trips(infos: self.logInfos, aggregation: aggregation)
        self.trips.compute()
        // rows is only a first guess, will really know once trips are computed
        super.init(rows: self.trips.infoCount + self.trips.tripCount + 1,
                   columns: self.fields.count + self.headers.count, frozenColumns: 1, frozenRows: 1)
    }
    
    //MARK: - delegate

    override func prepare() {
        
        self.cellHolders  = []
        self.geometries = []
        
        self.frozenColor = UIColor.secondarySystemBackground
        let titleAttributes : [NSAttributedString.Key:Any] = ViewConfig.shared.titleAttributes
        let cellAttributes : [NSAttributedString.Key:Any] = ViewConfig.shared.cellAttributes
        
        var row : Int = 0
        
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
        row += 1
        var tripIndex : Int = 0
        for trip in trips.trips {
            for info in trip.flightLogFileInfos {
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
                            self.cellHolders.append(CellHolder(numberWithUnit: nu))
                        }else{
                            self.cellHolders.append(CellHolder(string: "", attributes: cellAttributes))
                        }
                        geoIndex += 1
                    }
                    row += 1
                }else{
                    Logger.app.error("internal inconsistency")
                }
            }
            // Summary
            tripIndex += 1
            self.cellHolders.append(CellHolder(string:  "Trip Total", attributes: titleAttributes))
            self.cellHolders.append(CellHolder(string:  "", attributes: titleAttributes))
            self.cellHolders.append(CellHolder(string:  "", attributes: titleAttributes))
            self.cellHolders.append(CellHolder(string:  "", attributes: cellAttributes))
            self.cellHolders.append(CellHolder(string:  "", attributes: cellAttributes))
            var geoIndex = self.headers.count
            for field in fields {
                if let nu = trip.numberWithUnit(field: field) {
                    geometries[geoIndex].adjust(for: nu, numberAttribute: titleAttributes)
                    self.cellHolders.append(CellHolder(numberWithUnit: nu, attributes: titleAttributes))
                }else{
                    self.cellHolders.append(CellHolder(string: "", attributes: cellAttributes))
                }
                geoIndex += 1
            }
            self.highlightedBackgroundRows.insert(row)
            row += 1
        }
        if self.rowsCount != row {
            Logger.app.warning("Inconsistent row count \(self.rowsCount) \(row)")
        }
    }
}
