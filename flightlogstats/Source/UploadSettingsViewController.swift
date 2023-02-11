//
//  UploadSettingsViewController.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 05/02/2023.
//

import UIKit

class UploadSettingsViewController: UIViewController {
    weak var flightLogViewModel : FlightLogViewModel? = nil
    weak var summaryViewController : UIViewController? = nil
    
    @IBOutlet weak var flystoSwitch: UISwitch!
    @IBOutlet weak var savvySwitch: UISwitch!
    
    
    @IBAction func logoutSavvy(_ sender: Any) {
        SavvyRequests.clearCredential()
    }
    
    @IBAction func logoutFlysto(_ sender: Any) {
        FlyStoRequests.clearCredential()
    }
    
    @IBAction func forceUpload(_ sender: Any) {
        self.dismiss(animated: true)
        if let parent = self.summaryViewController {
            self.flightLogViewModel?.startServiceSynchronization(viewController: parent,force: true)
        }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.viewFromSettings()
    }

    @IBAction func uiControlChanged(_ sender: Any) {
        if (sender as? UISwitch) == self.savvySwitch {
            Settings.shared.savvyEnabled = self.savvySwitch.isOn
        }else if (sender as? UISwitch) == self.flystoSwitch {
            Settings.shared.flystoEnabled = self.flystoSwitch.isOn
        }
    }
    
    func viewFromSettings(){
        self.savvySwitch.isOn = Settings.shared.savvyEnabled
        self.flystoSwitch.isOn = Settings.shared.flystoEnabled
    }
}
