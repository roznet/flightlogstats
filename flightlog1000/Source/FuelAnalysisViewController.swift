//
//  FuelAnalysisViewController.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 21/06/2022.
//

import UIKit
import OSLog

class FuelAnalysisViewController: UIViewController, ViewModelDelegate {
    
    @IBOutlet weak var fuelTargetField: UITextField!
    @IBOutlet weak var fuelTargetSegment: UISegmentedControl!
    @IBOutlet weak var fuelTargetUnitSegment: UISegmentedControl!
    
    @IBOutlet weak var fuelAddedLeftField: UITextField!
    @IBOutlet weak var fuelAddedRightField: UITextField!
    @IBOutlet weak var fuelAddedUnitSegment: UISegmentedControl!
    
    @IBOutlet weak var fuelCollectionView: UICollectionView!
    
    var fuelDataSource : FlightSummaryFuelDataSource? = nil
    
    var flightLogViewModel : FlightLogViewModel? = nil
    var flightLogFileInfo : FlightLogFileInfo? { return self.flightLogViewModel?.flightLogFileInfo }
    
    func viewModelDidFinishBuilding(viewModel: FlightLogViewModel) {
        self.updateUI()
    }
    
    func viewModelHasChanged(viewModel: FlightLogViewModel) {
        self.flightLogViewModel = viewModel
        DispatchQueue.main.async {
            self.updateUI()
        }

    }
    

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.updateUI()
    }
    func updateUI(){
        AppDelegate.worker.async {
            
            if self.flightLogFileInfo?.flightSummary != nil {
                DispatchQueue.main.async {
                    if self.flightLogViewModel != nil && self.fuelCollectionView != nil {
                        self.fuelDataSource = self.flightLogViewModel?.fuelDataSource
                        self.fuelCollectionView.dataSource = self.fuelDataSource
                        self.fuelCollectionView.delegate = self.fuelDataSource
                        if let tableCollectionLayout = self.fuelCollectionView.collectionViewLayout as? TableCollectionViewLayout {
                            tableCollectionLayout.tableCollectionDelegate = self.fuelDataSource
                        }else{
                            Logger.app.error("Internal error: Inconsistent layout ")
                        }
                    }
                    
                    self.view.setNeedsDisplay()
                }
            }
        }
    }
}
