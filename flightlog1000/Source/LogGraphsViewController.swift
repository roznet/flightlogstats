//
//  LogGraphsViewController.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 21/06/2022.
//

import UIKit
import OSLog

class LogGraphsViewController: UIViewController, ViewModelDelegate {
    
    @IBOutlet weak var logListCollectionView: UICollectionView!
    var flightListDataSource : FlightListDataSource? = nil
    
    func viewModelDidFinishBuilding(viewModel: FlightLogViewModel) {
        
    }

    func viewModelHasChanged(viewModel: FlightLogViewModel) {
        
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        

        self.flightListDataSource = FlightListDataSource(displayContext: DisplayContext())
        self.logListCollectionView.dataSource = self.flightListDataSource
        self.logListCollectionView.delegate = self.flightListDataSource
        if let tableCollectionLayout = self.logListCollectionView.collectionViewLayout as? TableCollectionViewLayout {
            tableCollectionLayout.tableCollectionDelegate = self.flightListDataSource
        }else{
            Logger.app.error("Internal error: Inconsistent layout ")
        }

    }

}
