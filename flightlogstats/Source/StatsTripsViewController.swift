//
//  TripsStatsViewController.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 28/07/2022.
//

import UIKit
import OSLog

class StatsTripsViewController: UIViewController {
    @IBOutlet weak var logListCollectionView: UICollectionView!
    @IBOutlet weak var aggregationSegment: UISegmentedControl!
    
    var flightListDataSource : FlightListDataSource? = nil
    
    var aggregation : Trips.Aggregation = .trips
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.updateView()
        self.rebuildTable()
    }
    func rebuildTable() {
        let infos = FlightLogOrganizer.shared.flightLogFileRecords(request: .flightsOnly)
        self.flightListDataSource = FlightListDataSource(logFileRecords: infos, displayContext: DisplayContext(), aggregation: self.aggregation)
        
        self.logListCollectionView.dataSource = self.flightListDataSource
        self.logListCollectionView.delegate = self.flightListDataSource
        if let tableCollectionLayout = self.logListCollectionView.collectionViewLayout as? TableCollectionViewLayout {
            tableCollectionLayout.tableCollectionDelegate = self.flightListDataSource
        }else{
            Logger.app.error("Internal error: Inconsistent layout ")
        }
        
    }
    //MARK: - ui controls
    func updateView() {
        switch self.aggregation {
        case .trips:
            self.aggregationSegment.selectedSegmentIndex = 0
        case .months:
            self.aggregationSegment.selectedSegmentIndex = 1
        }
    }
    
    @IBAction func aggregationChanged(_ sender: Any) {
        if self.aggregationSegment.selectedSegmentIndex == 0 {
            self.aggregation = .trips
        }else if self.aggregationSegment.selectedSegmentIndex == 1 {
            self.aggregation = .months
        }
        self.rebuildTable()
    }
    
}
