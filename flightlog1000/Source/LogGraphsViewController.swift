//
//  LogGraphsViewController.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 21/06/2022.
//

import UIKit
import OSLog
import RZUtils
import RZUtilsUniversal

class LogGraphsViewController: UIViewController, ViewModelDelegate {

    @IBOutlet weak var graphView: GCSimpleGraphView!
    @IBOutlet weak var legsCollectionView: UICollectionView!
    
    var flightLogFileInfo : FlightLogFileInfo? { return self.flightLogViewModel?.flightLogFileInfo }
    var legsDataSource : FlightLegsDataSource? = nil
    
    var flightLogViewModel : FlightLogViewModel? = nil
    
    var graphField : FlightLogFile.Field? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.updateUI()
        
        NotificationCenter.default.addObserver(forName: .logFileInfoUpdated, object: nil, queue:nil){
            notification in
            DispatchQueue.main.async{
                self.updateUI()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.legsDataSource?.indexPathSelectedCallback = nil
        NotificationCenter.default.removeObserver(self)
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */
    func updateMinimumUI() {
        if self.legsCollectionView != nil {
            //self.legsCollectionView.isHidden = true
            //self.graphView.isHidden = true
        }
    }

    func legsTable(selected : IndexPath?) {
        if let selected = selected, let field = self.legsDataSource?.field(at: selected) {
            self.graphField = field
            self.updateUI()
        }
    }
    
    func updateUI(){
        if self.legsCollectionView == nil {
            // not ready
            return
        }
        AppDelegate.worker.async {
            if self.flightLogFileInfo?.flightSummary != nil {
                DispatchQueue.main.async {
                    if self.legsCollectionView != nil {
                        self.graphView.isHidden = false
                        self.legsCollectionView.isHidden = false
                        
                        if let legsDataSource = self.flightLogViewModel?.legsDataSource {
                            self.legsDataSource = legsDataSource
                            self.legsCollectionView.dataSource = self.legsDataSource
                            self.legsCollectionView.delegate = self.legsDataSource
                            self.legsDataSource?.indexPathSelectedCallback = { indexPath in self.legsTable(selected: indexPath ) }
                            
                            if let tableCollectionLayout = self.legsCollectionView.collectionViewLayout as? TableCollectionViewLayout {
                                tableCollectionLayout.tableCollectionDelegate = self.legsDataSource
                            }else{
                                Logger.app.error("Internal error: Inconsistent layout ")
                            }
                        }else{
                            self.legsDataSource = nil
                        }
                        
                        if self.graphField == nil {
                            self.graphField = .AltInd
                        }
                        let ds = self.flightLogViewModel?.graphDataSource(field: self.graphField!)
                        self.graphView.dataSource = ds
                        self.graphView.displayConfig = ds
                        self.graphView.setNeedsDisplay()
                        self.view.setNeedsDisplay()
                    }
                }
            }
        }
    }

    private var progress : ProgressReport? = nil
    
    // MARK: - Handle updates
    
    func viewModelDidFinishBuilding(viewModel : FlightLogViewModel){
        self.updateUI()
    }
    
    func viewModelHasChanged(viewModel: FlightLogViewModel) {
        let changed : Bool = !(self.flightLogViewModel?.isSameLog(as: viewModel.flightLogFileInfo) ?? false)
        self.flightLogViewModel = viewModel
        
        if changed {
            self.updateMinimumUI()
        }
        
        DispatchQueue.main.async {
            self.updateUI()
        }
    }

}
