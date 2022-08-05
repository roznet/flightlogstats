//
//  LogMapViewController.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 05/08/2022.
//

import UIKit
import MapKit
import OSLog
import RZUtils

class LogMapViewController: UIViewController, MKMapViewDelegate, ViewModelDelegate {

    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var legsCollectionView: UICollectionView!
    
    var flightLogFileInfo : FlightLogFileInfo? { return self.flightLogViewModel?.flightLogFileInfo }
    var legsDataSource : FlightLegsDataSource? = nil
    
    var flightLogViewModel : FlightLogViewModel? = nil
    private var mapViewOverlay : FlightDataMapOverlay? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        self.mapView.delegate = self
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
        NotificationCenter.default.removeObserver(self)
    }

    func updateMinimumUI() {
        if self.legsCollectionView != nil {
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
                        self.mapView.isHidden = false
                        self.legsCollectionView.isHidden = false
                        
                        if let legsDataSource = self.flightLogViewModel?.legsDataSource {
                            self.legsDataSource = legsDataSource
                            self.legsCollectionView.dataSource = self.legsDataSource
                            self.legsCollectionView.delegate = self.legsDataSource
                            if let tableCollectionLayout = self.legsCollectionView.collectionViewLayout as? TableCollectionViewLayout {
                                tableCollectionLayout.tableCollectionDelegate = self.legsDataSource
                            }else{
                                Logger.app.error("Internal error: Inconsistent layout ")
                            }
                        }else{
                            self.legsDataSource = nil
                        }
                        
                        if let overlay = self.flightLogFileInfo?.flightLog?.mapOverlayView {
                            if let oldOverlay = self.mapViewOverlay {
                                self.mapView.removeOverlay(oldOverlay)
                            }
                            self.mapViewOverlay = overlay
                            self.mapView.addOverlay(overlay)
                            self.mapView.setVisibleMapRect(overlay.boundingMapRect, edgePadding: .init(top: 5.0, left: 5.0, bottom: 5.0, right: 5.0), animated: true)
                        }
                        self.view.setNeedsDisplay()
                    }
                }
            }
        }
    }

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
    
    //MARK: - Mapview Delegate
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if (overlay as? FlightDataMapOverlay) == self.mapViewOverlay {
            return FlightDataMapOverlayView(overlay: overlay)
        }
        return MKOverlayRenderer()
    }
}
