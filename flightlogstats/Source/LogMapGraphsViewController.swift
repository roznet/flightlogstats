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
import MapKit

class LogMapGraphsViewController: UIViewController, ViewModelDelegate, MKMapViewDelegate {

    
    @IBOutlet weak var mapView: MKMapView!

    @IBOutlet weak var graphView: GCSimpleGraphView!
    @IBOutlet weak var legsCollectionView: UICollectionView!
    
    @IBOutlet weak var graphTypeSegment: UISegmentedControl!
    @IBOutlet weak var legTypeSegment: UISegmentedControl!
    
    var flightLogFileInfo : FlightLogFileRecord? { return self.flightLogViewModel?.flightLogFileInfo }
    var legsDataSource : FlightLegsDataSource? = nil
    
    var flightLogViewModel : FlightLogViewModel? = nil
    
    // start with two decent default
    var graphFields : [FlightLogFile.Field] = [.IAS, .AltInd]
    var selectedLeg : FlightLeg? = nil

    private var mapViewOverlay : FlightDataMapOverlay? = nil
    
    var graphEnabled = true
    var mapEnabled = true
    
    enum LegDisplayType {
        case waypoints
        case phasesOfFlight
        case comm
        case autopilot
    }
    
    enum GraphStyle {
        case singleGraph
        case twoGraphs
        case scatterPlot
    }
    
    var legDisplayType : LegDisplayType = .waypoints { didSet {
        switch self.legDisplayType {
        case .phasesOfFlight:
            self.flightLogViewModel?.legsByFields = [.FltPhase]
        case .waypoints:
            self.flightLogViewModel?.legsByFields = [.AtvWpt]
        case .comm:
            self.flightLogViewModel?.legsByFields = [.COM1,.COM2]
        case .autopilot:
            self.flightLogViewModel?.legsByFields = [.AfcsOn,.RollM,.PitchM]
        }
    }}
    var graphDisplayType : GraphStyle = .singleGraph
    
    var useLegsDataSource : FlightLegsDataSource?  {
        return self.flightLogViewModel?.legsDataSource
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.mapView.delegate = self
        
        self.mapView.isHidden = !self.mapEnabled
        self.graphView.isHidden = !self.graphEnabled
    }

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.updateUI()
        
        NotificationCenter.default.addObserver(forName: .logFileRecordUpdated, object: nil, queue:nil){
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
        if let selected = selected {
            if let field = self.legsDataSource?.field(at: selected),
               let leg = self.legsDataSource?.leg(at: selected){
                self.graphFields = self.graphFields.filter { $0 != field }
                self.graphFields.append(field)
                self.selectedLeg = leg
            }
            self.updateUI()
        }else{
            // just unselected row, remove highlight
            if self.selectedLeg != nil {
                self.selectedLeg = nil
                self.updateUI()
            }
        }
    }
    
    private func pushLetTypeViewToModel() {
        if !self.userInterfaceIsReady {
            return
        }

        if self.legTypeSegment.selectedSegmentIndex == 0 {
            self.legDisplayType = .waypoints
        }else if self.legTypeSegment.selectedSegmentIndex == 1 {
            self.legDisplayType = .phasesOfFlight
        }else if self.legTypeSegment.selectedSegmentIndex == 2 {
            self.legDisplayType = .comm
        }else if self.legTypeSegment.selectedSegmentIndex == 3 {
            self.legDisplayType = .autopilot
        }
    }
    
    @IBAction func segmentChanged(_ sender: UISegmentedControl) {
        if self.legTypeSegment == sender {
            self.pushLetTypeViewToModel()
            // may have to rebuild
            AppDelegate.worker.async {
                self.flightLogViewModel?.build()
            }
            
            self.updateUI()
            
        }else if self.graphTypeSegment == sender {
            if sender.selectedSegmentIndex == 0 {
                self.graphDisplayType = .singleGraph
            }else if sender.selectedSegmentIndex == 1 {
                self.graphDisplayType = .twoGraphs
            }else if sender.selectedSegmentIndex == 2 {
                self.graphDisplayType = .scatterPlot
            }
            self.updateUI()
        }
    }
    
    var userInterfaceIsReady : Bool { return self.legsCollectionView != nil }
    
    func updateUI(){
        if !self.userInterfaceIsReady {
            return
        }
        AppDelegate.worker.async {
            if self.flightLogFileInfo?.flightSummary != nil {
                DispatchQueue.main.async {
                    if self.legsCollectionView != nil {
                        
                        self.legsCollectionView.isHidden = false
                        if let legsDataSource = self.useLegsDataSource {
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

                        self.graphView.isHidden = !self.graphEnabled
                        if self.graphEnabled {
                            if self.graphDisplayType == .scatterPlot {
                                let ds = self.flightLogViewModel?.scatterDataSource(fields: self.graphFields.suffix(2))
                                self.graphView.dataSource = ds
                                self.graphView.displayConfig = ds
                            }else{
                                let ds = self.flightLogViewModel?.graphDataSource(fields: self.graphFields.suffix(self.graphDisplayType == .singleGraph ? 1 : 2), leg: self.selectedLeg)
                                self.graphView.dataSource = ds
                                self.graphView.displayConfig = ds
                            }
                            self.graphView.setNeedsDisplay()
                        }
                        
                        self.mapView.isHidden = !self.mapEnabled
                        if self.mapEnabled {
                            if let overlay = self.flightLogFileInfo?.flightLog?.mapOverlayView {
                                if let oldOverlay = self.mapViewOverlay {
                                    self.mapView.removeOverlay(oldOverlay)
                                }
                                if let selectedLeg = self.selectedLeg {
                                    overlay.highlightTimeRange = selectedLeg.timeRange
                                }else{
                                    overlay.highlightTimeRange = nil
                                }
                                self.mapViewOverlay = overlay
                                self.mapView.addOverlay(overlay)
                                self.mapView.setVisibleMapRect(overlay.highlightMapRect,
                                                               edgePadding: .init(top: 5.0, left: 5.0, bottom: 5.0, right: 5.0),
                                                               animated: true)
                            }
                        }
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
            self.pushLetTypeViewToModel()
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
