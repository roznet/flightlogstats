//
//  AircraftSummaryDataSource.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 18/12/2022.
//

import Foundation
import UIKit
import OSLog
import RZUtils
import RZUtilsSwift

class AircraftSummaryDataSource: TableDataSource {

    let aircraftRecord : AircraftRecord
    let displayContext : DisplayContext
    
    //
    //    Identifier
    //    Airframe Name
    //    Current Fuel Status
    //    Previous Flight Date
    //    Last Flight Date
    //    Last Airport
    //    Total Flights
    
    init(aircaftRecord : AircraftRecord, displayContext : DisplayContext = DisplayContext()){
        self.aircraftRecord = aircaftRecord
        self.displayContext = displayContext
        super.init(rows: 4, columns: 2, frozenColumns: 1, frozenRows: 1)
    }
    
    //MARK: - delegate
        
    var titleAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.boldSystemFont(ofSize: 14.0)]
    var cellAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize: 14.0)]
    
    func addLine(title : String, string : String) {
        self.cellHolders.append(CellHolder(string: title, attributes: self.titleAttributes))
        self.cellHolders.append(CellHolder(string: string, attributes: self.cellAttributes))
    }
    
    func addLine(title: String, date : Date?) {
        if let date = date {
            self.cellHolders.append(CellHolder(string: title, attributes: self.titleAttributes))
            self.cellHolders.append(CellHolder(string: self.displayContext.format(date: date),
                                               attributes: self.cellAttributes))
        }
    }
    
    func addLine(title: String, measurement : Measurement<Dimension>){
        
    }
    
    override func prepare() {
        
        self.cellHolders  = []
        self.geometries = []
        
        self.cellAttributes = ViewConfig.shared.cellAttributes
        self.titleAttributes = ViewConfig.shared.titleAttributes
        
        for title in [ "", "" ] {
            self.cellHolders.append(CellHolder(string: title, attributes: self.titleAttributes))
            let geometry = RZNumberWithUnitGeometry()
            geometry.defaultUnitAttribute = self.cellAttributes
            geometry.defaultNumberAttribute = self.cellAttributes
            geometry.numberAlignment = .decimalSeparator
            geometry.unitAlignment = .left
            geometry.alignment = .center
            self.geometries.append(geometry)
        }
        
        self.addLine(title: "Identifier", string: self.aircraftRecord.aircraftIdentifier)
        self.addLine(title: "Airframe", string: self.aircraftRecord.airframeName)
        self.addLine(title: "Last", date: self.aircraftRecord.lastestFlightDate)
    }
}
