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
class DetailSettingsViewController: UIViewController {
    
    @IBOutlet weak var tabFuelField: UITextField!
    @IBOutlet weak var maxFuelField: UITextField!
    @IBOutlet weak var gphField: UITextField!

    @IBOutlet weak var targetUnitSegment: UISegmentedControl!
    @IBOutlet weak var addedUnitSegment: UISegmentedControl!
    @IBOutlet private var labels : [UILabel]!
    @IBOutlet private var titleLabels : [UILabel]!
    
    // don't think we should be able change that...?
    let aircraftFuelUnit : UnitVolume = UnitVolume.gallons
    
    var enteredMaxFuel : FuelQuantity {
        get {
            if let maxFuel =  self.maxFuelField.text, let value = Double( maxFuel )  {
                return FuelQuantity(total: value, unit: self.aircraftFuelUnit)
            }
            return Settings.shared.aircraftPerformance.fuelMax
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
            return Settings.shared.aircraftPerformance.fuelTab
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
            return Settings.shared.aircraftPerformance.gph
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
        
        let aircraft = AircraftPerformance(fuelMax: self.enteredMaxFuel, fuelTab: self.enteredTabFuel, gph: self.enteredGph)
        Settings.shared.aircraftPerformance = aircraft
        
        NotificationCenter.default.post(name: .settingsViewControllerUpdate, object: self)
    }
    
    func pushModelToView() {
        let aircraft = Settings.shared.aircraftPerformance
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
    
    func update(segment : UISegmentedControl, for unit : UnitVolume){
        if unit == UnitVolume.gallons{
            segment.selectedSegmentIndex = 0
        }else if unit == UnitVolume.liters {
            segment.selectedSegmentIndex = 1
        }else{
            Logger.app.error("Invalid unit \(unit) for segment")
        }
    }
    
    func unit(for segment : UISegmentedControl) -> UnitVolume {
        if segment.selectedSegmentIndex == 0 {
            return UnitVolume.gallons
        }else if segment.selectedSegmentIndex == 1 {
            return UnitVolume.liters
        }
        Logger.app.error("Invalid segment for unit")
        return UnitVolume.gallons
    }

}
