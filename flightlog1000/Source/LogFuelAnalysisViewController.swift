//
//  FuelAnalysisViewController.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 21/06/2022.
//

import UIKit
import OSLog
import RZUtils

class LogFuelAnalysisViewController: UIViewController, ViewModelDelegate, UITextFieldDelegate {
    
    @IBOutlet weak var fuelTargetField: UITextField!
    @IBOutlet weak var fuelTargetSegment: UISegmentedControl!
    @IBOutlet weak var fuelTargetUnitSegment: UISegmentedControl!
    
    @IBOutlet weak var fuelAddedLeftField: UITextField!
    @IBOutlet weak var fuelAddedRightField: UITextField!
    @IBOutlet weak var fuelAddedUnitSegment: UISegmentedControl!
    
    @IBOutlet weak var fuelCollectionView: UICollectionView!
    
    @IBOutlet private var fixedLabels : [UILabel]!
    
    var fuelDataSource : FuelAnalysisDataSource? { return self.flightLogViewModel?.fuelAnalysisDataSource }
    
    var flightLogViewModel : FlightLogViewModel? = nil
    var flightLogFileInfo : FlightLogFileInfo? { return self.flightLogViewModel?.flightLogFileInfo }
    
    func viewModelDidFinishBuilding(viewModel: FlightLogViewModel) {
        self.updateUI()
    }
    
    func viewModelHasChanged(viewModel: FlightLogViewModel) {
        self.flightLogViewModel = viewModel
        DispatchQueue.main.async {
            self.setupViewFromModel()
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

        for label in self.fixedLabels {
            label.font = ViewConfig.shared.defaultBodyFont
        }
        self.fuelTargetField.font = ViewConfig.shared.defaultTextEntryFont
        self.fuelAddedLeftField.font = ViewConfig.shared.defaultTextEntryFont
        self.fuelAddedRightField.font = ViewConfig.shared.defaultTextEntryFont
        // Do any additional setup after loading the view.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.setupViewFromModel()
        self.updateUI()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.pushViewToModel()
    }
    
    //MARK: - field to view object links
    var fuelTargetUnit : GCUnit { return self.flightLogViewModel?.fuelTargetUnit ?? Settings.fuelStoreUnit }
    var fuelAddedUnit : GCUnit { return self.flightLogViewModel?.fuelAddedUnit ?? Settings.fuelStoreUnit }
    
    var enteredFuelTarget : FuelQuantity {
        get {
            if let targetFuel =  self.fuelTargetField.text, let value = Double( targetFuel )  {
                return FuelQuantity(total: value, unit: self.fuelTargetUnit)
            }
            return Settings.shared.targetFuel
        }
        set {
            let converted = newValue.convert(to: self.fuelTargetUnit)
            self.fuelTargetField.text = Self.fuelFormatter.string(from: NSNumber(floatLiteral: converted.total))
        }
    }

    var enteredFuelAdded : FuelQuantity {
        get {
            if let addedFuelLeft = self.fuelAddedLeftField.text, let left = Double( addedFuelLeft ),
               let addedFuelRight = self.fuelAddedRightField.text, let right = Double( addedFuelRight ){
                return FuelQuantity(left: left, right: right, unit: self.fuelAddedUnit)
            }
            return Settings.shared.addedFuel
        }
        set {
            let converted = newValue.convert(to: self.fuelAddedUnit)
            self.fuelAddedLeftField.text = Self.fuelFormatter.string(from: NSNumber(floatLiteral: converted.left))
            self.fuelAddedRightField.text = Self.fuelFormatter.string(from: NSNumber(floatLiteral: converted.right))
        }
    }

    static let fuelFormatter : NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.maximumFractionDigits = 1
        return numberFormatter
    }()
    
    
    func update(segment : UISegmentedControl, for unit : GCUnit){
        if unit.isEqual(to: GCUnit.usgallon() ){
            segment.selectedSegmentIndex = 0
        }else if unit.isEqual(to: GCUnit.liter()){
            segment.selectedSegmentIndex = 1
        }else{
            Logger.app.error("Invalid unit \(unit) for segment")
        }
    }
    
    func unit(for segment : UISegmentedControl) -> GCUnit {
        if segment.selectedSegmentIndex == 0 {
            return GCUnit.usgallon()
        }else if segment.selectedSegmentIndex == 1 {
            return GCUnit.liter()
        }
        Logger.app.error("Invalid segment for unit")
        return GCUnit.usgallon()
    }
    
    //MARK: - sync view and model
    private func pushViewToModel() {
        let inputs = FuelAnalysis.Inputs(targetFuel: self.enteredFuelTarget, addedfuel: self.enteredFuelAdded)        
        self.flightLogViewModel?.fuelAnalysisInputs = inputs
        self.flightLogViewModel?.fuelAddedUnit = self.unit(for: self.fuelAddedUnitSegment)
        self.flightLogViewModel?.fuelTargetUnit = self.unit(for: self.fuelTargetUnitSegment)
    }
        
    private func pushModelToView() {
        if let inputs = self.flightLogViewModel?.fuelAnalysisInputs {
            self.enteredFuelAdded = inputs.addedfuel
            self.enteredFuelTarget = inputs.targetFuel
        }
        self.update(segment: self.fuelTargetUnitSegment, for: self.fuelTargetUnit)
        self.update(segment: self.fuelAddedUnitSegment, for: self.fuelAddedUnit)
    }

    private func checkViewConsistency() {
        if let aircraft = self.flightLogViewModel?.aircraft {
            if self.enteredFuelTarget == aircraft.fuelMax {
                self.fuelTargetSegment.selectedSegmentIndex = 0
            }else if self.enteredFuelTarget == aircraft.fuelTab {
                self.fuelTargetSegment.selectedSegmentIndex = 1
            }else{
                self.fuelTargetSegment.selectedSegmentIndex = 2
            }
        }
    }
    
    private func setupViewFromModel() {
        // Make sure UI ready
        guard self.fuelTargetField != nil else { return }
        
        self.flightLogFileInfo?.ensureFuelRecord()
        if let record = self.flightLogFileInfo?.fuel_record {
            self.enteredFuelAdded = record.addedFuel
            self.enteredFuelTarget = record.targetFuel
        }else{
            let targetUnit = Settings.shared.unitTargetFuel
            let addedUnit = Settings.shared.unitAddedFuel
            let newInputs = FuelAnalysis.Inputs(targetFuel: Settings.shared.targetFuel.convert(to: targetUnit),
                                                addedfuel: Settings.shared.addedFuel.convert(to: addedUnit))
            if let viewModel = self.flightLogViewModel, viewModel.isValid(target: newInputs.targetFuel), viewModel.isValid(added: newInputs.addedfuel) {
                viewModel.fuelAnalysisInputs = newInputs
            }
        }
        self.update(segment: self.fuelTargetSegment, for: self.fuelTargetUnit)
        self.update(segment: self.fuelAddedUnitSegment, for: self.fuelAddedUnit)
        self.checkViewConsistency()
    }

    func updateUI(){
        AppDelegate.worker.async {
            self.flightLogViewModel?.build()
            if self.flightLogFileInfo?.flightSummary != nil {
                DispatchQueue.main.async {
                    if self.flightLogViewModel != nil && self.fuelCollectionView != nil {
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
    
    @IBAction func showConfig(_ sender: Any) {
        
    }
    @objc func segmentDidChange(_ segment : UISegmentedControl) {
        
        if segment == self.fuelTargetSegment {
            if segment.selectedSegmentIndex == 0 {
                if let newTarget = self.flightLogViewModel?.aircraft.fuelMax {
                    self.enteredFuelTarget = newTarget
                }
            }else if segment.selectedSegmentIndex == 1 {
                if let newTarget = self.flightLogViewModel?.aircraft.fuelTab {
                    self.enteredFuelTarget = newTarget
                }
            }
        }else if segment == self.fuelAddedUnitSegment {
            let startFuel = self.enteredFuelAdded
            self.flightLogViewModel?.fuelAddedUnit = self.unit(for: self.fuelAddedUnitSegment)
            self.enteredFuelAdded = startFuel
        }else if segment == self.fuelTargetUnitSegment {
            let startFuel = self.enteredFuelTarget
            self.flightLogViewModel?.fuelTargetUnit = self.unit(for: self.fuelTargetUnitSegment)
            self.enteredFuelTarget = startFuel
        }
        if self.flightLogViewModel != nil {
            self.pushViewToModel()
            self.updateUI()
        }
    }
    
    // MARK: - Text Field Editing and fuel values
    
    private func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        /*if let previousString = textField.text,
           let range = Range(range, in: previousString) {
            let newString = previousString.replacingCharacters(in: range, with: string)
        }*/
        return true
    }
    
    @objc func textViewDidChange(_ textView: UITextView) {
        self.pushViewToModel()
        self.checkViewConsistency()
        if self.flightLogViewModel != nil {
            self.updateUI()
        }
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }
}
