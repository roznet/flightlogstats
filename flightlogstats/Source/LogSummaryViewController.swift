//
//  LogDetailViewController.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 18/04/2022.
//

import UIKit
import OSLog
import RZUtils

class LogSummaryViewController: UIViewController,ViewModelDelegate {
    var logFileOrganizer = FlightLogOrganizer.shared
    
    @IBOutlet weak var openFlyStoButton: UIButton!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var name: UILabel!
    @IBOutlet weak var date: UILabel!
    
    @IBOutlet weak var remoteServiceButton: UIButton!
    @IBOutlet weak var remoteServiceStatus: UILabel!
    
    @IBOutlet weak var timeCollectionView: UICollectionView!
    @IBOutlet weak var fuelCollectionView: UICollectionView!
    @IBOutlet weak var legsCollectionView: UICollectionView!
    @IBOutlet weak var aircraftCollectionView: UICollectionView!
    
    var flightLogFileInfo : FlightLogFileRecord? { return self.flightLogViewModel?.flightLogFileRecord }
    var legsDataSource : FlightLegsDataSource? = nil
    var fuelDataSource : FlightSummaryFuelDataSource? = nil
    var timeDataSource : FlightSummaryTimeDataSource? = nil
    var aircraftDataSource : AircraftSummaryDataSource? = nil
    
    var flightLogViewModel : FlightLogViewModel? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPress))
        self.remoteServiceButton.addGestureRecognizer(longPress)
    }

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if self.flightLogViewModel?.shouldBuild ?? true {
            self.updateMinimumUI()
        }
        NotificationCenter.default.addObserver(forName: .logFileRecordUpdated, object: nil, queue:nil){
            notification in
            DispatchQueue.main.async{
                self.updateUI()
            }
        }
        NotificationCenter.default.addObserver(forName: .flightLogViewModelUploadFinished, object: nil, queue: nil){
            notification in
            DispatchQueue.main.async{
                self.updateUI()
            }
        }
        NotificationCenter.default.addObserver(forName: .settingsViewControllerUpdate, object: nil, queue: nil){
            notification in
            DispatchQueue.main.async{
                self.updateUI()
            }
        }
        // need to cehck if we still need that, had sometime the UI not setup right
        // when coming back from background
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil){
            notification in
            DispatchQueue.main.async {
                self.view.layoutIfNeeded()
            }
        }
        
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Actions
    
    @IBAction func exportButton(_ sender: Any) {
        if Settings.shared.savvyEnabled || Settings.shared.flystoEnabled {
            self.flightLogViewModel?.startServiceSynchronization(viewController: self)
        }else{
            self.showServiceConfigurationPopup()
        }
    }
    
    @objc func longPress(_ sender : Any) {
        // check if long press started
        if let longPress = sender as? UILongPressGestureRecognizer, longPress.state == .began {
            self.showServiceConfigurationPopup()
        }
    }
    func showServiceConfigurationPopup() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let vc = storyboard.instantiateViewController(withIdentifier: "uploadSettingViewController") as? UploadSettingsViewController {
            vc.modalPresentationStyle = .popover
            vc.popoverPresentationController?.sourceView = self.remoteServiceButton
            vc.popoverPresentationController?.sourceRect = self.remoteServiceButton.bounds
            vc.summaryViewController = self
            vc.flightLogViewModel = self.flightLogViewModel
            self.present(vc, animated: true, completion: nil)
        }
    }
    
    @IBAction func openFlySto(_ sender: Any) {
        if Settings.shared.flystoEnabled {
            self.flightLogViewModel?.startFlyStoLogFileUrl(viewController: self)
        }
    }
    func startAutomaticUploadIfNeeded() {
        if Settings.shared.uploadMethod == .automatic, let viewModel = self.flightLogViewModel {
            if viewModel.flightLogFileRecord.recordStatus == .parsed {
                viewModel.startServiceSynchronization(viewController: self)
            }
        }
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */
    func updateMinimumUI() {
        if self.name != nil {
            if let logname = self.flightLogFileInfo?.log_file_name {
                self.date.attributedText = NSAttributedString(string: "Loading", attributes: ViewConfig.shared.cellAttributes)
                self.name.attributedText = NSAttributedString(string: logname, attributes: ViewConfig.shared.cellAttributes)
                self.name.textColor = UIColor.systemGray
                
                self.remoteServiceStatus.attributedText = NSAttributedString(string: self.serviceStatusDescription, attributes: ViewConfig.shared.subTextAttributes)
                self.remoteServiceStatus.textColor = UIColor.systemGray
                self.remoteServiceButton.isEnabled = true
                self.openFlyStoButton.isHidden = !Settings.shared.flystoEnabled
            }else{
                self.date.attributedText = NSAttributedString(string: self.serviceStatusDescription, attributes: ViewConfig.shared.cellAttributes)
                self.name.attributedText = NSAttributedString(string: "", attributes: ViewConfig.shared.cellAttributes)
                self.remoteServiceStatus.attributedText = NSAttributedString(string: "Pending",attributes: ViewConfig.shared.subTextAttributes)
                self.name.textColor = UIColor.systemGray
                self.remoteServiceStatus.textColor = UIColor.systemGray
                self.remoteServiceButton.isEnabled = false
                self.openFlyStoButton.isHidden = false
            }
            self.timeCollectionView.isHidden = true
            self.fuelCollectionView.isHidden = true
            self.legsCollectionView.isHidden = true
            self.aircraftCollectionView.isHidden = true
        }
    }
    var serviceStatusDescription : String {
        return self.flightLogViewModel?.uploadStatusText ?? "Pending"
    }
    func updateUI(){
        AppDelegate.worker.async {
            if self.flightLogFileInfo?.flightSummary != nil {
                DispatchQueue.main.async {
                    if self.name != nil {
                        self.timeCollectionView.isHidden = false
                        self.fuelCollectionView.isHidden = false
                        self.legsCollectionView.isHidden = false
                        self.aircraftCollectionView.isHidden = false

                        self.remoteServiceStatus.attributedText = NSAttributedString(string: self.serviceStatusDescription,  attributes: ViewConfig.shared.subTextAttributes)
                        self.remoteServiceStatus.textColor = UIColor.systemGray
                        self.remoteServiceButton.isEnabled = true
                        self.openFlyStoButton.isHidden = !Settings.shared.flystoEnabled

                        if let logname = self.flightLogFileInfo?.log_file_name {
                            self.name.attributedText = NSAttributedString(string: logname, attributes: ViewConfig.shared.cellAttributes)
                            self.name.textColor = UIColor.systemGray
                        }else{
                            self.name.attributedText = NSAttributedString(string: "", attributes: ViewConfig.shared.cellAttributes)
                        }
                        let formatter = DateFormatter()
                        formatter.dateStyle = .medium
                        formatter.timeStyle = .short
                        if let date = self.flightLogFileInfo?.start_time {
                            self.date.attributedText = NSAttributedString(string: formatter.string(from: date), attributes: ViewConfig.shared.titleAttributes)
                        }else{
                            self.date.attributedText = NSAttributedString(string: "", attributes: ViewConfig.shared.titleAttributes)
                        }
                        
                        self.fuelDataSource = self.flightLogViewModel?.fuelDataSource
                        self.fuelCollectionView.dataSource = self.fuelDataSource
                        self.fuelCollectionView.delegate = self.fuelDataSource
                        if let tableCollectionLayout = self.fuelCollectionView.collectionViewLayout as? TableCollectionViewLayout {
                            tableCollectionLayout.tableCollectionDelegate = self.fuelDataSource
                        }else{
                            Logger.app.error("Internal error: Inconsistent layout ")
                        }
                        self.timeDataSource = self.flightLogViewModel?.timeDataSource
                        self.timeCollectionView.dataSource = self.timeDataSource
                        self.timeCollectionView.delegate = self.timeDataSource
                        if let tableCollectionLayout = self.timeCollectionView.collectionViewLayout as? TableCollectionViewLayout {
                            tableCollectionLayout.tableCollectionDelegate = self.timeDataSource
                        }else{
                            Logger.app.error("Internal error: Inconsistent layout ")
                        }
                        
                        self.aircraftDataSource = self.flightLogViewModel?.aircraftDataSource
                        self.aircraftCollectionView.dataSource = self.aircraftDataSource
                        self.aircraftCollectionView.delegate = self.aircraftDataSource
                        if let tableCollectionLayout = self.aircraftCollectionView.collectionViewLayout as? TableCollectionViewLayout {
                            tableCollectionLayout.tableCollectionDelegate = self.aircraftDataSource
                        }else{
                            Logger.app.error("Internal error: Inconsistent layout ")
                        }
                    }
                    
                    self.view.setNeedsDisplay()
                    
                    if let legsDataSource = self.flightLogViewModel?.legsDataSource {
                        self.legsDataSource = legsDataSource
                        self.legsCollectionView.dataSource = self.legsDataSource
                        self.legsCollectionView.delegate = self.legsDataSource
                        if let tableCollectionLayout = self.legsCollectionView.collectionViewLayout as? TableCollectionViewLayout {
                            tableCollectionLayout.tableCollectionDelegate = self.legsDataSource
                        }else{
                            Logger.app.error("Internal error: Inconsistent layout ")
                        }
                    }else{
                        self.legsDataSource = nil
                    }
                }
            }
        }
    }

    private var progress : ProgressReport? = nil
    
    // MARK: - Handle updates
    
    func viewModelDidFinishBuilding(viewModel : FlightLogViewModel){
        self.progressView.isHidden = true
        self.updateUI()
    }
    
    func viewModelHasChanged(viewModel: FlightLogViewModel) {
        let changed : Bool = !(self.flightLogViewModel?.isSameLog(as: viewModel.flightLogFileRecord) ?? false)
        self.flightLogViewModel = viewModel
        
        if changed {
            self.updateMinimumUI()
        }

        if self.progress == nil {
            self.progress = ProgressReport(message: .parsingInfo){
                report in
                DispatchQueue.main.async {
                    if case .progressing(let val) = report.state {
                        self.progressView.setProgress( Float(val), animated: true )
                    }
                }
            }
        }
        
        DispatchQueue.main.async {
            self.updateUI()
            if self.progressView != nil {
                self.progressView.setProgress(0.0, animated: false)
                self.progressView.isHidden = false
            }
            self.startAutomaticUploadIfNeeded()
        }
    }
    
}
