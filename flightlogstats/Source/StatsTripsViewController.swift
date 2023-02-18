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
    var flightListDataSource : FlightListDataSource? = nil
    
    var aggregation : Trips.Aggregation = .trips
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
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
}
