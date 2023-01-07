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
    @IBOutlet weak var fuelTotalizerStartField: UITextField!
    
    @IBOutlet weak var fuelTargetSegment: UISegmentedControl!
    @IBOutlet weak var fuelTargetUnitSegment: UISegmentedControl!
    
    @IBOutlet weak var fuelAddedLeftField: UITextField!
    @IBOutlet weak var fuelAddedRightField: UITextField!
    @IBOutlet weak var fuelAddedUnitSegment: UISegmentedControl!
    
    @IBOutlet weak var fuelCollectionView: UICollectionView!
    
    @IBOutlet weak var maxFuelSubLabel: UILabel!
    
    @IBOutlet private var fixedLabels : [UILabel]!
    @IBOutlet private var subFixedLabels : [UILabel]!
    
    var fuelDataSource : FuelAnalysisDataSource? { return self.flightLogViewModel?.fuelAnalysisDataSource }
    
    var flightLogViewModel : FlightLogViewModel? = nil
    var flightLogFileInfo : FlightLogFileRecord? { return self.flightLogViewModel?.flightLogFileInfo }
    
    //MARK: - delegate functions
    
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
        self.fuelTotalizerStartField.addTarget(self, action: #selector(self.textViewDidChange(_:)), for: .editingChanged)
        
        self.fuelTargetSegment.addTarget(self, action: #selector(self.segmentDidChange(_:)), for: .valueChanged)
        self.fuelTargetUnitSegment.addTarget(self, action: #selector(self.segmentDidChange(_:)), for: .valueChanged)
        self.fuelAddedUnitSegment.addTarget(self, action: #selector(self.segmentDidChange(_:)), for: .valueChanged)

        for label in self.fixedLabels {
            label.font = ViewConfig.shared.defaultBodyFont
        }
        for label in self.subFixedLabels {
            label.font = ViewConfig.shared.defaultSubFont
        }

        self.fuelTargetField.font = ViewConfig.shared.defaultTextEntryFont
        self.fuelAddedLeftField.font = ViewConfig.shared.defaultTextEntryFont
        self.fuelAddedRightField.font = ViewConfig.shared.defaultTextEntryFont
        self.fuelTotalizerStartField.font = ViewConfig.shared.defaultTextEntryFont
        // Do any additional setup after loading the view.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.flightLogViewModel?.displayContext.horizontalSizeClass = self.traitCollection.horizontalSizeClass

        self.setupViewFromModel()
        self.updateUI()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.pushViewToModel()
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !Settings.shared.fuelConfigFirstUseAcknowledged {
            let alert = UIAlertController(title: "First Use", message: "Please make sure you edit as necessary the configuration for your aircraft before use. This should not to be used as a primary flight planning and decision tool", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Acknowledged", style: .default, handler: { _ in Settings.shared.fuelConfigFirstUseAcknowledged = true } ) )
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    //MARK: - field to view object links
    var fuelTargetUnit : UnitVolume { return self.flightLogViewModel?.fuelTargetUnit ?? Settings.fuelStoreUnit }
    var fuelAddedUnit : UnitVolume { return self.flightLogViewModel?.fuelAddedUnit ?? Settings.fuelStoreUnit }
    
    var enteredtotalizerStart : FuelQuantity {
        get {
            if let totalizerStart =  self.fuelTotalizerStartField.text, let value = Double( totalizerStart )  {
                return FuelQuantity(total: value, unit: self.fuelTargetUnit)
            }
            return Settings.shared.targetFuel
        }
        set {
            let converted = newValue.converted(to: self.fuelTargetUnit)
            self.fuelTotalizerStartField.text = Self.fuelFormatter.string(from: NSNumber(floatLiteral: converted.total))
        }

    }
    
    var enteredFuelTarget : FuelQuantity {
        get {
            if let targetFuel =  self.fuelTargetField.text, let value = Double( targetFuel )  {
                return FuelQuantity(total: value, unit: self.fuelTargetUnit)
            }
            return Settings.shared.targetFuel
        }
        set {
            let converted = newValue.converted(to: self.fuelTargetUnit)
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
            let converted = newValue.converted(to: self.fuelAddedUnit)
            self.fuelAddedLeftField.text = Self.fuelFormatter.string(from: NSNumber(floatLiteral: converted.left))
            self.fuelAddedRightField.text = Self.fuelFormatter.string(from: NSNumber(floatLiteral: converted.right))
        }
    }

    static let fuelFormatter : NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.maximumFractionDigits = 1
        return numberFormatter
    }()
    
    
    func update(segment : UISegmentedControl, for unit : UnitVolume){
        if unit == UnitVolume.aviationGallon {
            segment.selectedSegmentIndex = 0
        }else if unit == UnitVolume.liters{
            segment.selectedSegmentIndex = 1
        }else{
            Logger.app.error("Invalid unit \(unit) for segment")
        }
    }
    
    func unit(for segment : UISegmentedControl) -> UnitVolume {
        if segment.selectedSegmentIndex == 0 {
            return UnitVolume.aviationGallon
        }else if segment.selectedSegmentIndex == 1 {
            return UnitVolume.liters
        }
        Logger.app.error("Invalid segment for unit")
        return UnitVolume.aviationGallon
    }
    
    //MARK: - sync view and model
    
    private func updateAircraftData() {
        // this should be sync'd with the view
        if let maxTextLabel = self.flightLogViewModel?.fuelMaxTextLabel {
            self.maxFuelSubLabel.text = maxTextLabel
        }
        if let maxFuel = self.flightLogViewModel?.aircraftPerformance.fuelMax {
            if maxFuel.totalMeasurement < self.enteredFuelTarget.totalMeasurement {
                self.enteredFuelTarget = maxFuel
            }
            if maxFuel.totalMeasurement < self.enteredtotalizerStart.totalMeasurement {
                self.enteredtotalizerStart = maxFuel
            }
        }
    }
    
    private func pushViewToModel() {
        self.updateAircraftData()
        
        let inputs = FuelAnalysis.Inputs(targetFuel: self.enteredFuelTarget, addedfuel: self.enteredFuelAdded, totalizerStartFuel: self.enteredtotalizerStart)
        self.flightLogViewModel?.fuelAnalysisInputs = inputs
        self.flightLogViewModel?.fuelAddedUnit = self.unit(for: self.fuelAddedUnitSegment)
        self.flightLogViewModel?.fuelTargetUnit = self.unit(for: self.fuelTargetUnitSegment)
    }
        
    private func pushModelToView() {
        self.updateAircraftData()
        
        if let inputs = self.flightLogViewModel?.fuelAnalysisInputs {
            self.enteredFuelAdded = inputs.addedfuel
            self.enteredFuelTarget = inputs.targetFuel
            self.enteredtotalizerStart = inputs.totalizerStartFuel
        }
        self.update(segment: self.fuelTargetUnitSegment, for: self.fuelTargetUnit)
        self.update(segment: self.fuelAddedUnitSegment, for: self.fuelAddedUnit)
    }

    private func checkViewConsistency() {
        if let aircraft = self.flightLogViewModel?.aircraftPerformance {
            if self.enteredFuelTarget == aircraft.fuelMax {
                self.fuelTargetSegment.selectedSegmentIndex = 0
            }else if self.enteredFuelTarget == aircraft.fuelTab {
                self.fuelTargetSegment.selectedSegmentIndex = 1
            }else{
                self.fuelTargetSegment.selectedSegmentIndex = 2
            }
        }
    }
    
    private func estimatePreviousTotalizerStart() -> FuelQuantity? {
        // do we have previous flight info?
        var previousStart : FuelQuantity? = nil
        if let info = self.flightLogFileInfo {
            previousStart = info.estimatedTotalizerStart
        }
        return previousStart
    }
    
    private func setupViewFromModel() {
        // Make sure UI ready
        guard self.fuelTargetField != nil else { return }
        
        AppDelegate.worker.async {
            self.flightLogFileInfo?.ensureFuelRecord()
            DispatchQueue.main.async {
                self.updateAircraftData()
                if let record = self.flightLogFileInfo?.fuel_record {
                    self.enteredFuelAdded = record.addedFuel
                    self.enteredFuelTarget = record.targetFuel
                    self.enteredtotalizerStart = record.totalizerStartFuel
                }else{
                    let targetUnit = Settings.shared.unitTargetFuel
                    let addedUnit = Settings.shared.unitAddedFuel
                    let newInputs = FuelAnalysis.Inputs(targetFuel: Settings.shared.targetFuel.converted(to: targetUnit),
                                                        addedfuel: FuelQuantity.zero.converted(to: addedUnit),
                                                        totalizerStartFuel: Settings.shared.totalizerStartFuel.converted(to: targetUnit))
                    if let viewModel = self.flightLogViewModel, viewModel.isValid(target: newInputs.targetFuel), viewModel.isValid(added: newInputs.addedfuel) {
                        viewModel.fuelAnalysisInputs = newInputs
                    }
                }
                self.update(segment: self.fuelTargetSegment, for: self.fuelTargetUnit)
                self.update(segment: self.fuelAddedUnitSegment, for: self.fuelAddedUnit)
                self.checkViewConsistency()
            }
        }
        
    }

    
    //MARK: - Update UI
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
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let detailSettings = (segue.destination as? DetailSettingsViewController) {
            Logger.app.info("Show detail")
            detailSettings.flightLogViewModel = self.flightLogViewModel
            NotificationCenter.default.addObserver(forName: .settingsViewControllerUpdate, object: nil, queue: nil){
                _ in
                Logger.ui.info("Update Fuel Analysis for settings change")
                self.pushModelToView()
                self.updateUI()
                AppDelegate.worker.async {
                    self.flightLogFileInfo?.saveContext()
                }
            }
        }
    }
    
    // MARK: - Segment and units

    @objc func segmentDidChange(_ segment : UISegmentedControl) {
        
        if segment == self.fuelTargetSegment {
            if segment.selectedSegmentIndex == 0 {
                if let newTarget = self.flightLogViewModel?.aircraftPerformance.fuelMax {
                    self.enteredFuelTarget = newTarget
                }
            }else if segment.selectedSegmentIndex == 1 {
                if let newTarget = self.flightLogViewModel?.aircraftPerformance.fuelTab {
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
