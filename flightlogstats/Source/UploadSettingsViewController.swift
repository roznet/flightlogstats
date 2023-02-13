//
//  UploadSettingsViewController.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 05/02/2023.
//

import UIKit
import OSLog

class UploadSettingsViewController: UIViewController {
    weak var flightLogViewModel : FlightLogViewModel? = nil
    weak var summaryViewController : UIViewController? = nil
    
    @IBOutlet weak var flystoSwitch: UISwitch!
    @IBOutlet weak var savvySwitch: UISwitch!
    
    
    @IBAction func logoutSavvy(_ sender: Any) {
        SavvyRequests.clearCredential()
        NotificationCenter.default.post(name: .settingsViewControllerUpdate, object: self)
    }
    
    @IBAction func logoutFlysto(_ sender: Any) {
        FlyStoRequests.clearCredential()
        NotificationCenter.default.post(name: .settingsViewControllerUpdate, object: self)
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
        NotificationCenter.default.post(name: .settingsViewControllerUpdate, object: self)
    }
    
    func viewFromSettings(){
        self.savvySwitch.isOn = Settings.shared.savvyEnabled
        self.flystoSwitch.isOn = Settings.shared.flystoEnabled
        
        if let savvyStatus = self.flightLogViewModel?.savvyStatus {
            if let date = self.flightLogViewModel?.savvyUpdateDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                Logger.ui.info("Savvy: \(savvyStatus) Last upload \(formatter.string(from: date))")
            }
        }
        if let flystoStatus = self.flightLogViewModel?.flystoStatus{
            if let date = self.flightLogViewModel?.flystoUpdateDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                Logger.ui.info("Flysto: \(flystoStatus) Last upload \(formatter.string(from: date))")
            }
        }
    }
}
