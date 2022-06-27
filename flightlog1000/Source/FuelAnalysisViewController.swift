//
//  FuelAnalysisViewController.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 21/06/2022.
//

import UIKit
import OSLog
import RZUtils

class FuelAnalysisViewController: UIViewController, ViewModelDelegate, UITextFieldDelegate {
    
    @IBOutlet weak var fuelTargetField: UITextField!
    @IBOutlet weak var fuelTargetSegment: UISegmentedControl!
    @IBOutlet weak var fuelTargetUnitSegment: UISegmentedControl!
    
    @IBOutlet weak var fuelAddedLeftField: UITextField!
    @IBOutlet weak var fuelAddedRightField: UITextField!
    @IBOutlet weak var fuelAddedUnitSegment: UISegmentedControl!
    
    @IBOutlet weak var fuelCollectionView: UICollectionView!
    
    var fuelDataSource : FuelAnalysisDataSource? = nil
    
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

        self.fuelAddedLeftField.delegate = self
        self.fuelTargetField.delegate = self
        self.fuelAddedRightField.delegate = self
        
        self.fuelTargetField.addTarget(self, action: #selector(self.textViewDidChange(_:)), for: .editingChanged)
        self.fuelAddedRightField.addTarget(self, action: #selector(self.textViewDidChange(_:)), for: .editingChanged)
        self.fuelAddedLeftField.addTarget(self, action: #selector(self.textViewDidChange(_:)), for: .editingChanged)
        
        self.fuelTargetSegment.addTarget(self, action: #selector(self.segmentDidChange(_:)), for: .valueChanged)
        self.fuelTargetUnitSegment.addTarget(self, action: #selector(self.segmentDidChange(_:)), for: .valueChanged)
        self.fuelAddedUnitSegment.addTarget(self, action: #selector(self.segmentDidChange(_:)), for: .valueChanged)
        

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
                        
                        
                        self.fuelDataSource = self.flightLogViewModel?.fuelAnalysisDataSource
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
    
    // MARK: - Segment and units
    
    @objc func segmentDidChange(_ segment : UISegmentedControl) {
        
        if segment == self.fuelTargetSegment {
            
        }else {
            let unit : GCUnit = segment.selectedSegmentIndex == 0 ? GCUnit.usgallon() : GCUnit.liter()
            
            if segment == self.fuelAddedUnitSegment {
                print( "fuel added unit \(unit)")
            }else if segment == self.fuelTargetUnitSegment {
                
            }
        }
    }
    
    // MARK: - Text Field Editing and fuel values
    
    private func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if let previousString = textField.text,
           let range = Range(range, in: previousString) {
            let newString = previousString.replacingCharacters(in: range, with: string)
            print(newString)
        }
        return true
    }
    
    @objc func textViewDidChange(_ textView: UITextView) {
        if let value = Double(textView.text) {
            
            if textView == self.fuelTargetField {
                Logger.app.info("Target changed \(value)")
            }else if( textView == self.fuelAddedLeftField ){
                Logger.app.info("Left changed \(value)")
            }else if( textView == self.fuelAddedRightField ){
                Logger.app.info("Right changed \(value)")
            }
        }
    }
}
