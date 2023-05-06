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
   
    //Status Labels
    @IBOutlet weak var flystoMainStatusLabel: UILabel!
    @IBOutlet weak var flystoSubStatusLabel: UILabel!
    
    @IBOutlet weak var savvyMainStatusLabel: UILabel!
    @IBOutlet weak var savvySubStatusLabel: UILabel!
    
    @IBAction func logoutSavvy(_ sender: Any) {
        SavvyRequest.clearCredential()
        NotificationCenter.default.post(name: .settingsViewControllerUpdate, object: self)
    }
    
    @IBAction func logoutFlysto(_ sender: Any) {
        FlyStoRequest.clearCredential()
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
        self.viewFromSettings()
    }
    func updateStatus(status : RemoteServiceRecord.Status?,
                      on : Bool,
                      date : Date?,
                      label : UILabel,
                      sublabel : UILabel,
                      message : String){
        label.textColor = UIColor.label
        sublabel.textColor = UIColor.systemGray

        if !on {
            label.attributedText = NSAttributedString(string: "Disabled", attributes: ViewConfig.shared.cellAttributes)
            sublabel.attributedText = NSAttributedString(string: "", attributes: ViewConfig.shared.subTextAttributes)
            label.textColor = UIColor.systemGray
            sublabel.textColor = UIColor.systemGray
            return
        }else{
            label.textColor = UIColor.label
            sublabel.textColor = UIColor.systemGray
        }

        if let status = status {
            label.attributedText = NSAttributedString(string: status.description, attributes: ViewConfig.shared.cellAttributes)
            if let date = date {
                let formatter = RelativeDateTimeFormatter()
                sublabel.attributedText = NSAttributedString(string: formatter.localizedString(for: date, relativeTo: Date()), attributes: ViewConfig.shared.subTextAttributes)
                
                Logger.ui.info("\(message): \(status) Last upload \(formatter.localizedString(for: date, relativeTo: Date()))")
            }else{
                sublabel.text = ""
            }
        }else{
            label.attributedText = NSAttributedString(string: "Not logged in", attributes: ViewConfig.shared.cellAttributes)
            sublabel.attributedText = NSAttributedString(string: "", attributes: ViewConfig.shared.subTextAttributes)
        }
    }
    func viewFromSettings(){
        self.savvySwitch.isOn = Settings.shared.savvyEnabled
        self.flystoSwitch.isOn = Settings.shared.flystoEnabled
        self.updateStatus(status: self.flightLogViewModel?.flystoStatus, on: Settings.shared.flystoEnabled, date: self.flightLogViewModel?.flystoUpdateDate, label: self.flystoMainStatusLabel, sublabel: self.flystoSubStatusLabel, message: "flysto")
        self.updateStatus(status: self.flightLogViewModel?.savvyStatus, on: Settings.shared.savvyEnabled, date: self.flightLogViewModel?.savvyUpdateDate, label: self.savvyMainStatusLabel, sublabel: self.savvySubStatusLabel, message: "savvy")
        
    }
}
