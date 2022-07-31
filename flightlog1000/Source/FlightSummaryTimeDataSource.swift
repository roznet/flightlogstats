//
//  FlightSummaryDataSource.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 12/06/2022.
//

import UIKit
import OSLog

class FlightSummaryTimeDataSource: TableDataSource {
    let flightSummary : FlightSummary
    let displayContext : DisplayContext
        
    init(flightSummary : FlightSummary, displayContext : DisplayContext = DisplayContext()){
        self.flightSummary = flightSummary
        self.displayContext = displayContext
        
        super.init(rows: 0, columns: 6, frozenColumns: 1, frozenRows: 1)
        
    }
    
    //MARK: - delegate
        
    var titleAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.boldSystemFont(ofSize: 14.0)]
    var cellAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize: 14.0)]
    
    /// Prepare a row of the table
    /// - Parameters:
    ///   - title: Title label
    ///   - description: a text for description
    ///   - since: this will display elapsed time in the range in time format (should be start = turn on, end beginning of event/section to report)
    ///   - elapsed: this will display elapsed time in the range in decimal format (should be start of period (start of moving, start of flight, etc) to end of period (moving, flight, etc)
    func addLine(title : String, description : String, since : TimeRange? = nil, elapsed : TimeRange? = nil){
        self.cellHolders.append(CellHolder(string: title, attributes: self.titleAttributes))
        self.cellHolders.append(CellHolder(string: description, attributes: self.cellAttributes))
        
        if let date = since?.end {
            self.cellHolders.append(CellHolder(string: self.displayContext.format(time: date),
                                                           attributes: self.cellAttributes))
        }else{
            self.cellHolders.append(CellHolder(string: "", attributes: self.cellAttributes))
        }
        
        if let since = since, since.elapsed > 0 {
            self.cellHolders.append(CellHolder(string: self.displayContext.formatHHMM(timeRange: since),
                                                           attributes: self.cellAttributes))
        }else{
            self.cellHolders.append(CellHolder(string: "", attributes: self.cellAttributes))
        }
        if let elapsed = elapsed {
            self.cellHolders.append(CellHolder(string: self.displayContext.formatHHMM(timeRange: elapsed),
                                                           attributes: self.cellAttributes))
            self.cellHolders.append(CellHolder(string: self.displayContext.formatDecimal(timeRange: elapsed),
                                                           attributes: self.cellAttributes))
        }else{
            self.cellHolders.append(CellHolder(string: "", attributes: self.cellAttributes))
            self.cellHolders.append(CellHolder(string: "", attributes: self.cellAttributes))
        }
        
        self.rowsCount += 1
    }
    
    //                 Value    Time   SinceStart  Elapsed   Logbook
    //    Start        Airport
    //    Taxi                   17:00   5:00      4:00       0.2
    //    Takeoff                X        X
    //    Landing      Airport   X        X
    //    Parked
    //    Shutdown
    //
    

    override func prepare() {
        
        self.cellHolders  = []
        self.geometries   = []
        self.rowsCount = 0
        
        self.cellAttributes = ViewConfig.shared.cellAttributes
        self.titleAttributes = ViewConfig.shared.titleAttributes

        for title in [ "", "", "Time", "Since Start", "Elapsed", "Logbook" ] {
            self.cellHolders.append(CellHolder(string: title, attributes: self.titleAttributes))
        }
        self.rowsCount += 1
        
        if let hobbs = self.flightSummary.hobbs,
           let airport = self.flightSummary.startAirport{
            self.addLine(title: "Start",
                            description: self.displayContext.format(airport: airport),
                            since: hobbs.startTo(start: hobbs))
            
        }else{
            self.addLine(title: "Start", description: "")
        }
        
        if  let hobbs = self.flightSummary.hobbs,
            let moving = self.flightSummary.moving {
            let taxi = hobbs.startTo(start: moving)
            self.addLine(title: "Taxi", description: "", since: taxi)
        }else{
            self.addLine(title: "Taxi", description: "")
        }
        
        if let hobbs = self.flightSummary.hobbs,
            let flying = self.flightSummary.flying {
            let takeoff = hobbs.startTo(start: flying)
            self.addLine(title: "Takeoff", description: "", since: takeoff)
            let landing = hobbs.startTo(end: flying)
            self.addLine(title: "Landing", description: "", since: landing, elapsed: flying)
        }else{
            self.addLine(title: "Takeoff", description: "")
            self.addLine(title: "Landing", description: "")
        }

        if  let hobbs = self.flightSummary.hobbs,
            let moving = self.flightSummary.moving {
            let taxi = hobbs.startTo(end: moving)
            self.addLine(title: "Parked", description: "", since: taxi, elapsed: moving)
        }else{
            self.addLine(title: "Parked", description: "")
        }

        if let hobbs = self.flightSummary.hobbs {
            var endAirport = ""
            if let airport = self.flightSummary.endAirport {
                endAirport = self.displayContext.format(airport: airport)
            }

            self.addLine(title: "Shutdown", description: endAirport, since: hobbs, elapsed: hobbs)
        }else{
            self.addLine(title: "Shutdown", description: "")
        }
    }
}
