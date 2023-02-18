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
    var logInfos : [FlightLogFileRecord]
    
    var trips : Trips
    let displayContext : DisplayContext
    
    let fields : [FlightSummary.Field]
    let headers : [String]
    
    //               Total    Left   Right
    //    Start
    //    End
    //    Remaining
    
    init(logInfos: [FlightLogFileRecord],
         displayContext : DisplayContext = DisplayContext(),
         aggregation : Trips.Aggregation = .trips){
        self.fields = [.Hobbs, .Flying,  .Distance, .GroundSpeed, .Altitude, .GpH, .NmpG,  .FuelTotalizer, .FuelUsed, .FuelStart, .FuelEnd ]
        self.headers = [ "Date", "From", "To", "Start", "End"]
        self.displayContext = displayContext
        self.logInfos = logInfos
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
            if field.equivalentLogField == .Lcl_Time {
                geometry.unitAlignment = .hide
            }
            self.geometries.append(geometry)
            self.cellHolders.append(CellHolder(string: field.rawValue, attributes: titleAttributes))
        }
        row += 1
        var tripIndex : Int = 0
        for trip in trips.trips {
            for info in trip.flightLogFileRecords {
                if let summary = info.flightSummary, let hobbs = summary.hobbs {
                    self.cellHolders.append(CellHolder(string:  self.displayContext.format(date: hobbs.start), attributes: titleAttributes))
                    self.cellHolders.append(CellHolder(string:  self.displayContext.format(airport: summary.startAirport, style: .icaoOnly), attributes: titleAttributes))
                    self.cellHolders.append(CellHolder(string:  self.displayContext.format(airport: summary.endAirport, style: .icaoOnly), attributes: titleAttributes))
                    self.cellHolders.append(CellHolder(string:  self.displayContext.format(time: hobbs.start), attributes: cellAttributes))
                    self.cellHolders.append(CellHolder(string:  self.displayContext.format(time: hobbs.end), attributes: cellAttributes))
                    var geoIndex = self.headers.count
                    for field in fields {
                        if let measurement = summary.measurement(for: field) {
                            let dv = self.displayContext.displayedValue(field: field.equivalentLogField, measurement: measurement)
                            dv.adjust(geometry: geometries[geoIndex])
                            self.cellHolders.append(dv.cellHolder(attributes: cellAttributes))
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
                if let nu = trip.measurement(field: field) {
                    let dv = self.displayContext.displayedValue(field: field.equivalentLogField, measurement: nu)
                    dv.adjust(geometry: geometries[geoIndex], numberAttribute: titleAttributes)
                    self.cellHolders.append(dv.cellHolder(attributes: titleAttributes))
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
