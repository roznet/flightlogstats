//
//  AppSettingsViewController.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 29/11/2022.
//

import UIKit

class AppSettingsViewController: UIViewController {

    private let importMenuConfig : [(Settings.ImportMethod,String)] = [ (.automatic, "Automatic"),
                                                              (.fromDate, "From Date"),
                                                              (.selectedFile, "Selected File"),
                                                              (.sinceLastImport, "Since Last Import") ]
    override func viewDidLoad() {
        super.viewDidLoad()

        var menuAction : [UIAction] = []
        for (method,title) in importMenuConfig {
            menuAction.append(UIAction(title: title, image: nil, identifier: nil, discoverabilityTitle: nil, attributes: [], state: .off, handler: { _ in
                Settings.shared.importMethod = method
                self.viewFromSettings()
            }))
        }
        
        self.importMethodButton.menu = UIMenu(title: "Import Method", image: nil, identifier: nil, options: [], children: menuAction)
    }
    
    @IBAction func doneButton(_ sender: Any) {
        self.dismiss(animated: true)
    }
    
    @IBOutlet weak var savvySwitch: UISwitch!
    @IBOutlet weak var flyStoSwitch: UISwitch!
    @IBOutlet weak var importMethodButton: UIButton!
    @IBOutlet weak var datePicker: UIDatePicker!
    
    
    @IBAction func uiControlChanged(_ sender: Any) {
        if (sender as? UISwitch) == self.savvySwitch {
            Settings.shared.savvyEnabled = self.savvySwitch.isOn
        }else if (sender as? UISwitch) == self.flyStoSwitch {
            Settings.shared.flystoEnabled = self.flyStoSwitch.isOn
        }else if (sender as? UIDatePicker) == self.datePicker {
            Settings.shared.importStartDate = self.datePicker.date
        }
        
        NotificationCenter.default.post(name: .settingsViewControllerUpdate, object: self)
    }
    
    func viewFromSettings(){
        self.savvySwitch.isOn = Settings.shared.savvyEnabled
        self.flyStoSwitch.isOn = Settings.shared.flystoEnabled
        self.datePicker.date = Settings.shared.importStartDate
        
        for (method,title) in self.importMenuConfig {
            if Settings.shared.importMethod == method {
                self.importMethodButton.setTitle(title, for: .normal)
                for child in self.importMethodButton.menu!.children {
                    guard let action = child as? UIAction else {
                        continue
                    }
                    action.state = action.title == title ? .on : .off
                }
                break
            }
        }
        
    }

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.viewFromSettings()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }

}
