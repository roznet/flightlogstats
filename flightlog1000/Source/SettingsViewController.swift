//
//  SettingsViewController.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 04/07/2022.
//

import UIKit

class SettingsViewController: UIViewController {
    
    @IBOutlet weak var tabFuelField: UITextField!
    @IBOutlet weak var maxFuelField: UITextField!
    @IBOutlet weak var gphField: UITextField!

    var aircraft : Aircraft? = nil
    
    static let fuelFormatter : NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.maximumFractionDigits = 1
        return numberFormatter
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let aircraft = Settings.shared.aircraft
        self.aircraft = aircraft
        self.maxFuelField.text = Self.fuelFormatter.string(from: NSNumber(floatLiteral: aircraft.fuelMax.total))
        self.tabFuelField.text = Self.fuelFormatter.string(from: NSNumber(floatLiteral: aircraft.fuelTab.total))
        self.gphField.text = Self.fuelFormatter.string(from: NSNumber(floatLiteral: aircraft.gph))
    }
    
    

}
