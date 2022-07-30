//
//  FlightSummaryDataSource.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 12/06/2022.
//

import UIKit
import OSLog

class FlightSummaryTimeDataSource: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, TableCollectionDelegate {
    let flightSummary : FlightSummary
    let displayContext : DisplayContext
    
    private var attributedCells : [NSAttributedString] = []

    var frozenColumns : Int = 1
    var frozenRows : Int = 1
    
    private(set) var sections : Int = 0
    private(set) var items : Int = 6
    
    init(flightSummary : FlightSummary, displayContext : DisplayContext = DisplayContext()){
        self.flightSummary = flightSummary
        self.displayContext = displayContext
        
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
    func prepareRow(title : String, description : String, since : TimeRange? = nil, elapsed : TimeRange? = nil){
        self.attributedCells.append(NSAttributedString(string: title, attributes: self.titleAttributes))
        self.attributedCells.append(NSAttributedString(string: description, attributes: self.cellAttributes))
        
        if let date = since?.end {
            self.attributedCells.append(NSAttributedString(string: self.displayContext.format(time: date),
                                                           attributes: self.cellAttributes))
        }else{
            self.attributedCells.append(NSAttributedString(string: "", attributes: self.cellAttributes))
        }
        
        if let since = since, since.elapsed > 0 {
            self.attributedCells.append(NSAttributedString(string: self.displayContext.formatHHMM(timeRange: since),
                                                           attributes: self.cellAttributes))
        }else{
            self.attributedCells.append(NSAttributedString(string: "", attributes: self.cellAttributes))
        }
        if let elapsed = elapsed {
            self.attributedCells.append(NSAttributedString(string: self.displayContext.formatHHMM(timeRange: elapsed),
                                                           attributes: self.cellAttributes))
            self.attributedCells.append(NSAttributedString(string: self.displayContext.formatDecimal(timeRange: elapsed),
                                                           attributes: self.cellAttributes))
        }else{
            self.attributedCells.append(NSAttributedString(string: "", attributes: self.cellAttributes))
            self.attributedCells.append(NSAttributedString(string: "", attributes: self.cellAttributes))
        }
    }
    
    //                 Value    Time   SinceStart  Elapsed   Logbook
    //    Start        Airport
    //    Taxi                   17:00   5:00      4:00       0.2
    //    Takeoff                X        X
    //    Landing      Airport   X        X
    //    Parked
    //    Shutdown
    //
    

    func prepare() {
        
        self.attributedCells  = []
        self.sections = 0
        
        for title in [ "", "", "Time", "Since Start", "Elapsed", "Logbook" ] {
            self.attributedCells.append(NSAttributedString(string: title, attributes: self.titleAttributes))
        }
        self.sections += 1
        
        if let hobbs = self.flightSummary.hobbs,
           let airport = self.flightSummary.startAirport{
            self.prepareRow(title: "Start",
                            description: self.displayContext.format(airport: airport),
                            since: hobbs.startTo(start: hobbs))
            
        }else{
            self.prepareRow(title: "Start", description: "")
        }
        self.sections += 1
        
        if  let hobbs = self.flightSummary.hobbs,
            let moving = self.flightSummary.moving {
            let taxi = hobbs.startTo(start: moving)
            self.prepareRow(title: "Taxi", description: "", since: taxi)
        }else{
            self.prepareRow(title: "Taxi", description: "")
        }
        self.sections += 1
        
        if let hobbs = self.flightSummary.hobbs,
            let flying = self.flightSummary.flying {
            let takeoff = hobbs.startTo(start: flying)
            self.prepareRow(title: "Takeoff", description: "", since: takeoff)
            let landing = hobbs.startTo(end: flying)
            self.prepareRow(title: "Landing", description: "", since: landing, elapsed: flying)
        }else{
            self.prepareRow(title: "Takeoff", description: "")
            self.prepareRow(title: "Landing", description: "")
        }
        self.sections += 2

        if  let hobbs = self.flightSummary.hobbs,
            let moving = self.flightSummary.moving {
            let taxi = hobbs.startTo(end: moving)
            self.prepareRow(title: "Parked", description: "", since: taxi, elapsed: moving)
        }else{
            self.prepareRow(title: "Parked", description: "")
        }
        self.sections += 1

        if let hobbs = self.flightSummary.hobbs {
            var endAirport = ""
            if let airport = self.flightSummary.endAirport {
                endAirport = self.displayContext.format(airport: airport)
            }

            self.prepareRow(title: "Shutdown", description: endAirport, since: hobbs, elapsed: hobbs)
        }else{
            self.prepareRow(title: "Shutdown", description: "")
        }
        self.sections += 1
    }
    
    func attributedString(at indexPath : IndexPath) -> NSAttributedString {
        let index = indexPath.section * self.items + indexPath.item
        return self.attributedCells[index]
    }
    func size(at indexPath: IndexPath) -> CGSize {
        return self.attributedString(at: indexPath).size()
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return self.sections
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.items
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TableCollectionViewCell", for: indexPath)
        if let tableCell = cell as? TableCollectionViewCell {
            tableCell.label.attributedText = self.attributedString(at: indexPath)
            
            if indexPath.section < self.frozenRows || indexPath.item < self.frozenColumns{
                tableCell.backgroundColor = UIColor.systemCyan
            }else{
                if indexPath.section % 2 == 0{
                    tableCell.backgroundColor = UIColor.systemBackground
                }else{
                    tableCell.backgroundColor = UIColor.systemGroupedBackground
                }
            }
        }
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Logger.app.info("Selected \(indexPath)")
    }

}
