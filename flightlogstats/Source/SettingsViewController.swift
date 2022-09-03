//
//  SettingsViewController.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 04/07/2022.
//

import UIKit
import OSLog
import RZUtils

extension Notification.Name {
    static let settingsViewControllerUpdate : Notification.Name = Notification.Name("Notification.Name.settingsViewControllerUpdate")
}
class SettingsViewController: UIViewController {
    
    @IBOutlet weak var tabFuelField: UITextField!
    @IBOutlet weak var maxFuelField: UITextField!
    @IBOutlet weak var gphField: UITextField!

    @IBOutlet weak var targetUnitSegment: UISegmentedControl!
    @IBOutlet weak var addedUnitSegment: UISegmentedControl!
    @IBOutlet private var labels : [UILabel]!
    @IBOutlet private var titleLabels : [UILabel]!
    
    // don't think we should be able change that...?
    let aircraftFuelUnit : GCUnit = GCUnit.usgallon()
    
    var enteredMaxFuel : FuelQuantity {
        get {
            if let maxFuel =  self.maxFuelField.text, let value = Double( maxFuel )  {
                return FuelQuantity(total: value, unit: self.aircraftFuelUnit)
            }
            return Settings.shared.aircraft.fuelMax
        }
        set {
            let converted = newValue.convert(to: self.aircraftFuelUnit)
            self.maxFuelField.text = Self.fuelFormatter.string(from: NSNumber(floatLiteral: converted.total))
        }
    }

    var enteredTabFuel : FuelQuantity {
        get {
            if let tabFuel =  self.tabFuelField.text, let value = Double( tabFuel )  {
                return FuelQuantity(total: value, unit: self.aircraftFuelUnit)
            }
            return Settings.shared.aircraft.fuelTab
        }
        set {
            let converted = newValue.convert(to: self.aircraftFuelUnit)
            self.tabFuelField.text = Self.fuelFormatter.string(from: NSNumber(floatLiteral: converted.total))
        }
    }

    var enteredGph : Double {
        get {
            if let gph =  self.gphField.text, let value = Double( gph )  {
                return value
            }
            return Settings.shared.aircraft.gph
        }
        set {
            self.tabFuelField.text = Self.fuelFormatter.string(from: NSNumber(floatLiteral: newValue))
        }
    }
    
    static let fuelFormatter : NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.maximumFractionDigits = 1
        return numberFormatter
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        self.tabFuelField.font = ViewConfig.shared.defaultTextEntryFont
        self.maxFuelField.font = ViewConfig.shared.defaultTextEntryFont
        self.gphField.font = ViewConfig.shared.defaultTextEntryFont
        
        for label in self.labels {
            label.font = ViewConfig.shared.defaultBodyFont
        }
        for label in self.titleLabels {
            label.font = ViewConfig.shared.defaultTitleFont
        }
        
    }

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.pushModelToView()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.pushViewToModel()
    }
    
    func pushViewToModel() {
        Settings.shared.unitAddedFuel = self.unit(for: self.addedUnitSegment)
        Settings.shared.unitTargetFuel = self.unit(for: self.targetUnitSegment)
        
        let aircraft = Aircraft(fuelMax: self.enteredMaxFuel, fuelTab: self.enteredTabFuel, gph: self.enteredGph)
        Settings.shared.aircraft = aircraft
        
        NotificationCenter.default.post(name: .settingsViewControllerUpdate, object: self)
    }
    
    func pushModelToView() {
        let aircraft = Settings.shared.aircraft
        self.enteredGph = aircraft.gph
        self.enteredTabFuel = aircraft.fuelTab
        self.enteredMaxFuel = aircraft.fuelMax
        
        self.update(segment: self.addedUnitSegment, for: Settings.shared.unitAddedFuel)
        self.update(segment: self.targetUnitSegment, for: Settings.shared.unitTargetFuel)
    }
    
    //MARK: - UI updates
    
    @objc func segmentDidChange(_ segment : UISegmentedControl){
        self.pushViewToModel()
    }
    @objc func textFieldDidChange(_ textView : UITextField) {
        self.pushViewToModel()
    }
    
    //MARK: - Helpers
    
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

}