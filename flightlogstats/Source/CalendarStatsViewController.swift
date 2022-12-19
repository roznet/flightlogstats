//
//  CalendarStatsViewController.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 14/08/2022.
//

import UIKit
import OSLog

class CalendarStatsViewController: UIViewController {
    @IBOutlet weak var logListCollectionView: UICollectionView!
    var flightListDataSource : FlightListDataSource? = nil
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let infos = FlightLogOrganizer.shared.actualFlightLogFileInfos
        self.flightListDataSource = FlightListDataSource(logInfos: infos, displayContext: DisplayContext(), aggregation: .months)
        
        self.logListCollectionView.dataSource = self.flightListDataSource
        self.logListCollectionView.delegate = self.flightListDataSource
        if let tableCollectionLayout = self.logListCollectionView.collectionViewLayout as? TableCollectionViewLayout {
            tableCollectionLayout.tableCollectionDelegate = self.flightListDataSource
        }else{
            Logger.app.error("Internal error: Inconsistent layout ")
        }

    }


}
