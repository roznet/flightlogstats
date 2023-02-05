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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let infos = FlightLogOrganizer.shared.flightLogFileInfos(request: .flightsOnly)
        self.flightListDataSource = FlightListDataSource(logInfos: infos, displayContext: DisplayContext(), aggregation: .trips)
        
        self.logListCollectionView.dataSource = self.flightListDataSource
        self.logListCollectionView.delegate = self.flightListDataSource
        if let tableCollectionLayout = self.logListCollectionView.collectionViewLayout as? TableCollectionViewLayout {
            tableCollectionLayout.tableCollectionDelegate = self.flightListDataSource
        }else{
            Logger.app.error("Internal error: Inconsistent layout ")
        }

    }
}
