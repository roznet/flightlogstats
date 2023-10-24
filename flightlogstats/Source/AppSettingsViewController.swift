//
//  AppSettingsViewController.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 29/11/2022.
//

import UIKit
import WebKit
class AppSettingsViewController: UIViewController {

    private let importMenuConfig : [(Settings.ImportMethod,String)] = [
        (.automatic, "Automatic"),
        (.last24h, "Last 24 hours"),
        (.last7d, "Last 7 days"),
        (.fromDate, "From Date"),
        (.selectedFile, "Selected File"),
        (.sinceLastImport, "Since Last Import")
    ]
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
    
    @IBOutlet weak var helpView: WKWebView!
    @IBAction func doneButton(_ sender: Any) {
        self.dismiss(animated: true)
    }
    
    @IBOutlet weak var savvyLabel: UILabel!
    @IBOutlet weak var flyStoLabel: UILabel!
    @IBOutlet weak var savvySwitch: UISwitch!
    @IBOutlet weak var flyStoSwitch: UISwitch!
    
    @IBOutlet weak var uploadMethodSwitch: UISwitch!
    @IBOutlet weak var importMethodButton: UIButton!
    @IBOutlet weak var datePicker: UIDatePicker!
    
    
    @IBAction func uiControlChanged(_ sender: Any) {
        if (sender as? UISwitch) == self.savvySwitch {
            Settings.shared.savvyEnabled = self.savvySwitch.isOn
        }else if (sender as? UISwitch) == self.flyStoSwitch {
            Settings.shared.flystoEnabled = self.flyStoSwitch.isOn
        }else if (sender as? UIDatePicker) == self.datePicker {
            Settings.shared.importStartDate = self.datePicker.date
        }else if (sender as? UISwitch) == self.uploadMethodSwitch {
            Settings.shared.uploadMethod = self.uploadMethodSwitch.isOn ? .automatic : .manual
        }
        
        NotificationCenter.default.post(name: .settingsViewControllerUpdate, object: self)
    }
    
    func viewFromSettings(){
        self.savvySwitch.isOn = Settings.shared.savvyEnabled
        self.flyStoSwitch.isOn = Settings.shared.flystoEnabled
        self.datePicker.date = Settings.shared.importStartDate
        self.uploadMethodSwitch.isOn = Settings.shared.uploadMethod == .automatic
        
        if Settings.shared.importMethod == .fromDate {
            self.datePicker.isHidden = false
        }else{
            self.datePicker.isHidden = true
        }
        
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
        self.updateHelp()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }

    func updateHelp() {
        let buildString = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let versionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        
        var versionHTML = ""
        if let buildString = buildString,
            let versionString = versionString {
            if buildString.hasPrefix(versionString) {
                versionHTML = "<h1>Version \(versionString)</h1>"
            }else{
                versionHTML = "<p>Version <b>\(versionString) (\(buildString))</b></p>"
            }
        }
        
        
        let htmlString : String = """
        <!DOCTYPE html>
        <html>
        <head>
        <style>
            body {
                font-family: -apple-system, system-ui, sans-serif;
                font-size: 16px;
            }
            h1 {
                font-size: 18px;
            }
            h2 {
                font-size: 16px;
            }
        </style>
        <body>
        \(versionHTML)
        <h1>Help</h1>
        <h2>Import Method</h2>
        <p>To import logs, insert an SD Card, press the + button and select the root of the card. The app will then search recursively all the log files present on the SD Card. Here is what each import method will do.</p>
        <ul>
        <li><b>Automatic</b> will search recursively and automatically import from the SD Card any log file not currently in the app</li>
        <li><b>Last 24 hours</b> will search recursively and automatically import from the SD Card any log file not currently in the app that was created in the last 24 hours</li>
        <li><b>Last 7 days</b> will search recursively and automatically import from the SD Card any log file not currently in the app that was created in the last 7 days</li>
        <li><b>From Date</b> will only import new files not the the app that are more recent than the selected date and will ignore any files older</li>
        <li><b>Since Last Import</b> the first time will import all the files on the card, but subsequently will only import files that are more recent than the last import. So for example if you then insert an SD Card with older files, they will be ignored</li>
        <li><b>Selected File</b> will only import the files that are explicitely selected, and will not do any recursive search. If you select this option in the open dialog box you need to select the specific files you want to import</li>
        </ul>
        <h2>Upload Automatically</h2>
        <p>If this is enabled, the app will attempt to upload automatically any file currently displayed that wasn't yet uploaded. If it is not selected you need to press the upload button to start the upload of the current file to the remote service.</p>
        <p>Note that if the file was already successfully uploaded, the app will not attempt to upload again. You can do a long press on the upload button, which will bring up a menu with the option to force the upload</p>
        </body>
        </html>
        """
        
        
        self.helpView.loadHTMLString(htmlString, baseURL: nil)
    }
}
