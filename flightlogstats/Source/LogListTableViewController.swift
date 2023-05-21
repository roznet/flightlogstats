//
//  ViewController.swift
//  flightlog1000
//
//  Created by Brice Rosenzweig on 18/04/2022.
//

import UIKit
import RZUtils
import RZUtilsSwift
import RZUtilsTouch
import UniformTypeIdentifiers
import OSLog

protocol LogSelectionDelegate : AnyObject {
    func selectlogInfo(_ info : FlightLogFileRecord)
    var logInfoIsSelected : Bool { get }
}

class LogListTableViewController: UITableViewController, UIDocumentPickerDelegate, UISearchResultsUpdating {

    var logInfoList : [FlightLogFileRecord] = []
    var fullLogInfoList : [FlightLogFileRecord] = []
    var aircraftsList : [AircraftRecord] = []
    
    var logFileOrganizer = FlightLogOrganizer.shared
    
    weak var delegate : LogSelectionDelegate? = nil
    weak var userInterfaceModeManager : UserInterfaceModeManager? = nil
    
    var searchController : UISearchController = UISearchController()
    var isSearchBarEmpty : Bool { return searchController.searchBar.text?.isEmpty ?? true }
    
    enum DisplayMode {
        case flights
        case aircrafts
    }
    var filterEmpty = true
    var displayMode : DisplayMode = .flights
    
    func flightInfo(at indexPath : IndexPath) -> FlightLogFileRecord? {
        return self.logInfoList[indexPath.row]
    }
    
    func aircraft(at indexPath : IndexPath) -> AircraftRecord? {
        return self.aircraftsList[indexPath.row]
    }
    
    // for iphone, or start in list more delegate may not be instantiated yet
    func ensureDelegate(){
        if self.delegate == nil {
            if let detailViewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "LogDetailTabBarController") as? LogTabBarController {
             self.delegate = detailViewController
            }else{
                Logger.app.error("Could not create detailViewController from storyboard")
            }
        }
    }

    //MARK: - progress overlay
    var progressReportOverlay : ProgressReportOverlay? = nil
    
    
    //MARK: - ui interactions (menu, search, button, etc)
    
    func moreFunctionMenu() -> UIMenu {
        var menuItems : [UIAction] = [
            UIAction(title: "Force Refresh", image: UIImage(systemName: "arrow.clockwise")){
                _ in
                self.buildList()
                self.tableView.reloadData()
            },
            UIAction(title: "Delete/Restore Logs", image: UIImage(systemName: "minus.circle")){
                _ in
                self.buildList()
                if self.tableView.isEditing {
                    self.tableView.setEditing(false, animated: true)
                }else{
                    self.tableView.setEditing(true, animated: true)
                }
                self.updateButtons()
            },
            UIAction(title: self.displayMode == .flights ? "Show Aircrafts" : "Show Flights",
                     image: UIImage(systemName: self.displayMode == .flights ? "airplane" :  "point.topleft.down.curvedto.point.filled.bottomright.up")){
                _ in
                self.displayMode = self.displayMode == .aircrafts ? .flights : .aircrafts
                self.buildList()
                self.tableView.reloadData()
                self.updateButtons()
            },
            UIAction(title: self.filterEmpty ? "Show non-flights" : "Show flights only",
                     image: UIImage(systemName: self.filterEmpty ? "eye" : "eye.slash")){
                _ in
                self.filterEmpty = !self.filterEmpty
                self.buildList()
                self.tableView.reloadData()
                self.updateButtons()
            },
            UIAction(title: "Settings", image: UIImage(systemName: "gearshape")){
                _ in
                let storyboard : UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
                let vc = storyboard.instantiateViewController(identifier: "appSettingsViewController")
                vc.modalPresentationStyle = .fullScreen
                self.present(vc, animated: true)
            },
            /**/
            UIAction(title: "Rebuild Info", image: UIImage(systemName: "plus.circle")){
                _ in
                Logger.app.info("Rebuild info")
                self.logFileOrganizer.updateRecords(count: 1000, force: true)
            },/**/
            ]
#if DEBUG
        menuItems.append(contentsOf: [
            UIAction(title: "Delete last", image: UIImage(systemName: "minus.circle")){
                _ in
                if let info = self.logFileOrganizer.first(request: .flightsOnly), let log_file_name = info.log_file_name {
                    Logger.ui.info("Deleting \(log_file_name)")
                    self.logFileOrganizer.delete(info: info)
                }
            },
            UIAction(title: "Rebuild Info", image: UIImage(systemName: "plus.circle")){
                _ in
                Logger.app.info("Rebuild info")
                self.logFileOrganizer.updateRecords(count: 1000, force: true)
            },
            UIAction(title: "Reset Database", image: UIImage(systemName: "minus.circle")){
                _ in
                Logger.app.info("Reset All")
                self.logFileOrganizer.deleteAndResetDatabase()
            },
            UIAction(title: "Reset Files and Database", image: UIImage(systemName: "minus.circle")){
                _ in
                Logger.app.info("Reset All")
                self.logFileOrganizer.deleteLocalFilesAndDatabase()
            },
            UIAction(title: "Try Overlay", image: UIImage(systemName: "minus.circle")){
                _ in
                Logger.app.info("Reset All")
                self.progressReportOverlay?.displayOverlay()
            }
            ])
#endif
        
        return UIMenu( options: .displayInline, children: menuItems)
        
    }
    
    func updateSearchResults(for searchController: UISearchController) {
        self.updateSearchedList()
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
    func updateButtons() {
        // Do any additional setup after loading the view.
        let addButton = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(addLog(button:)))
        let moreFunctionButton = UIBarButtonItem(title: "More", image: UIImage(systemName: "ellipsis.circle"), menu: self.moreFunctionMenu())
        
        let donebutton = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(done(button:)))
        
        let rightButton = self.tableView.isEditing ? donebutton : moreFunctionButton
        
        self.navigationItem.leftBarButtonItem = addButton
        
        if self.userInterfaceModeManager?.userInterfaceMode == .stats {
            let planeButton = UIBarButtonItem(image: UIImage(systemName: "airplane.circle"), style: .plain, target: self, action: #selector(sum(button:)))
            self.navigationItem.rightBarButtonItems = [rightButton, planeButton]
        }else{ // this include the case userInterfaceModeManager is nil
            let sumButton = UIBarButtonItem(image: UIImage(systemName: "sum"), style: .plain, target: self, action: #selector(sum(button:)))
            self.navigationItem.rightBarButtonItems = [rightButton, sumButton]
        }

    }
    
    
    //MARK: - UIViewController
    override func viewDidLoad() {
        super.viewDidLoad()
        self.updateButtons()
        
        self.tableView.estimatedRowHeight = 100
        self.tableView.rowHeight = UITableView.automaticDimension
        
        self.searchController.searchResultsUpdater = self
        self.searchController.obscuresBackgroundDuringPresentation = false
        self.searchController.searchBar.placeholder = "Search Flights"
        
        self.navigationItem.searchController = self.searchController
        self.navigationItem.hidesSearchBarWhenScrolling = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if self.progressReportOverlay == nil, let navigationController = self.navigationController {
            self.progressReportOverlay = ProgressReportOverlay(viewController: navigationController)
        }
        self.logFileOrganizer.ensureProgressReport() {
            progress in
            self.progressReportOverlay?.update(for: progress)
        }
        NotificationCenter.default.addObserver(forName: .localFileListChanged, object: nil, queue: nil){
            _ in
            Logger.ui.info("local file list changed, updating log list")
            self.buildList()
        }
        NotificationCenter.default.addObserver(forName: .newFileUploaded, object: nil, queue: nil){
            _ in
            Logger.ui.info("New file uploaded, updating log list")
            self.buildList()

        }
        
        NotificationCenter.default.addObserver(forName: .ErrorOccured, object: AppDelegate.errorManager, queue: nil) {
            _ in
            if let error = AppDelegate.errorManager.popLast() {
                Logger.ui.info("Reporting error \(error.localizedDescription)")
            }else{
                Logger.ui.info("No error to report")
            }
        }

        self.buildList()
    }
    

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }
    
    //MARK: - TableViewController
    
    enum TableSection : Int, CaseIterable {
        case statistics = 0, flights, aircrafts
        
        init?(indexPath : IndexPath) {
            self.init(rawValue: indexPath.section)
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return TableSection.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch TableSection(rawValue: section) {
        case .flights:
            switch self.displayMode {
            case .flights:
                return self.logInfoList.count
            case .aircrafts:
                return 0
            }
        case .statistics:
            return 1
        case .aircrafts:
            switch self.displayMode {
            case .flights:
                return 0
            case .aircrafts:
                return self.aircraftsList.count
            }
        case .none:
            return 0
        }
    }
    // aircraft:
    // Id, Last Flight date, last light airport
    // number of flights, last flight fuel
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch TableSection(indexPath: indexPath) {
        case .flights:
            let cell = tableView.dequeueReusableCell(withIdentifier: "flightlogcell", for: indexPath)
            if let cell = cell as? LogListTableViewCell,
               let info = self.flightInfo(at: indexPath) {
                cell.update(minimum: info)
                if info.recordStatus == .parsed || info.recordStatus == .quickParsed {
                    cell.update(with: info)
                }else{
                    AppDelegate.worker.async {
                        let _ = info.flightSummary
                        DispatchQueue.main.async {
                            cell.update(with: info)
                        }
                    }
                }
            }
            return cell
        case .aircrafts:
            let cell = tableView.dequeueReusableCell(withIdentifier: "aircraftcell", for: indexPath)
            if let cell = cell as? AircraftTableViewCell,
               let aircraft = self.aircraft(at: indexPath){
                cell.update(aircraft: aircraft, trip: self.aircraftTrips[aircraft.systemId])
            }
            return cell
        case .statistics:
            let cell = UITableViewCell(style: .default, reuseIdentifier: "flightstatscell")
            var content = cell.defaultContentConfiguration()
            content.text = "Display Statistics"
            content.textProperties.font = ViewConfig.shared.defaultTitleFont
            content.image = UIImage(systemName: "sum")
            
            cell.contentConfiguration = content
            cell.backgroundColor = UIColor.systemGroupedBackground
            return cell
        case .none:
            return UITableViewCell(frame: .zero)
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch TableSection(indexPath: indexPath) {
        case .statistics:
            return 50.0
        case .flights:
            return 100.0
        case .none:
            return 0.0
        case .aircrafts:
            return 100.0
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch TableSection(indexPath: indexPath) {
        case .flights:
            if let info = self.flightInfo(at: indexPath){
                if self.isEditing == true {
                    Logger.ui.info("Is editing")
                }
                self.ensureDelegate()
                self.delegate?.selectlogInfo(info)
                self.userInterfaceModeManager?.userInterfaceMode = .detail
                self.updateButtons()
            }
        case .statistics:
            self.userInterfaceModeManager?.userInterfaceMode = .stats
            self.updateButtons()
        case .aircrafts:
            return
        case .none:
            return
        }
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let logCell = (cell as? LogListTableViewCell) {
            NotificationCenter.default.addObserver(forName: .logFileRecordUpdated, object: nil, queue: nil){
                notification in
                if let info = (notification.object as? FlightLogFileRecord) {
                    if logCell.shouldRefresh(for: info) {
                        DispatchQueue.main.async {
                            if let file_name = info.log_file_name {
                                Logger.ui.info("refresh cell for \(file_name)")
                            }
                            logCell.refresh()
                        }
                    }
                }
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let logCell = (cell as? LogListTableViewCell) {
            NotificationCenter.default.removeObserver(logCell)
        }
    }
    
    //MARK: - UITableView Editing
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        switch TableSection(indexPath: indexPath) {
        case .flights:
            return true
        case .aircrafts:
            return false
        case .statistics:
            return false
        case .none:
            return false
        }
    }
    
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        return .insert
    }
    
    override func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String? {
        return "Ignore"
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        switch TableSection(indexPath: indexPath) {
        case .flights:
            if let info = self.flightInfo(at: indexPath){
                Logger.app.info("Delete \(info)")
            }

        case .aircrafts:
            break
        case .statistics,.none:
            break
        }

    }
    
    //MARK: - build list functionality
    
    func buildList() {
        if self.filterEmpty {
            self.fullLogInfoList = self.logFileOrganizer.flightLogFileRecords(request: .flightsOnly)
            DispatchQueue.main.async {
                self.updateSearchedList()
                self.buildAircraftList()
                self.tableView.reloadData()
                self.ensureOneDetailDisplayed()
            }
        }else{
            self.fullLogInfoList = self.logFileOrganizer.flightLogFileRecords(request: .all)
            self.updateSearchedList()
            self.buildAircraftList()
            self.tableView.reloadData()
            self.ensureOneDetailDisplayed()
        }
    }
    private var aircraftTrips : [AircraftRecord.SystemId : Trip] = [:]
    private func buildAircraftList() {
        self.aircraftsList = self.logFileOrganizer.aircraftRecords
        self.aircraftTrips = [:]
        for aircraft in self.aircraftsList {
            let records = self.logFileOrganizer.flightLogFileRecords(request: .flightsOnly, filter: self.logFileOrganizer.listFilter(aircrafts: [aircraft]))
            self.aircraftTrips[aircraft.systemId] = Trip(flightRecords: records, label: aircraft.aircraftIdentifier)
        }
        self.aircraftsList.sort() {
            l,r in
            if let ldate = l.lastestFlightDate, let rdate = r.lastestFlightDate {
                return ldate > rdate
            }
            return l.aircraftIdentifier < r.aircraftIdentifier
        }
        Logger.app.info("Build aircraft list")
    }

    private func ensureOneDetailDisplayed() {
        if let delegate = self.delegate, !delegate.logInfoIsSelected {
            if let info = self.logInfoList.first  {
                delegate.selectlogInfo(info)
            }else if let info = self.logFileOrganizer.first(request: .flightsOnly) {
                delegate.selectlogInfo(info)
            }
        }
    }
        
    func updateSearchedList() {
        if self.isSearchBarEmpty {
            self.logInfoList = self.fullLogInfoList
        }else if let searchText = self.searchController.searchBar.text {
            self.logInfoList = self.fullLogInfoList.filter { $0.contains(searchText) }
        }
    }
    
    //MARK: - add functionality
    
    @objc func sum(button : UIBarButtonItem) {
        self.ensureDelegate()
        if self.userInterfaceModeManager?.userInterfaceMode == .detail {
            self.userInterfaceModeManager?.userInterfaceMode = .stats
        }else{
            self.userInterfaceModeManager?.userInterfaceMode = .detail
        }
        self.updateButtons()
    }
    
    @objc func done(button: UIBarButtonItem){
        self.tableView.setEditing(false, animated: true)
        self.updateButtons()
    }
    
    @objc func addLog(button : UIBarButtonItem){
        // mac should select files, ios just import folder
        var uttypes : [UTType] = [ .folder ]
        var multipleSelection : Bool = false
        if Settings.shared.importMethod == .selectedFile {
            uttypes = [ .commaSeparatedText,.folder]
            multipleSelection = true
        }
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: uttypes)
        documentPicker.allowsMultipleSelection = multipleSelection
        documentPicker.delegate = self
        present(documentPicker, animated: true)
    }
    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.progressReportOverlay?.prepareOverlay(message: .addingFiles)
        var method : FlightLogOrganizer.LogSelectionMethod = .allMissingFromFolder
        switch Settings.shared.importMethod {
        case .selectedFile:
            method = .selectedFile(urls)
        case .sinceLastImport:
            method = .sinceLatestImportedFile
        case .fromDate:
            method = .afterDate(Settings.shared.importStartDate)
        case .automatic:
            method = .allMissingFromFolder
        }
        FlightLogOrganizer.search(in: urls) {
            result in
            switch result {
            case .success(let logurls):
                let missing = self.logFileOrganizer.filterMissing(urls: logurls)
                if missing.count > 50 {
                    self.importLargeNumberOfLogs(urls: logurls, method: method)
                }else{
                    self.logFileOrganizer.importAndAddRecordsForFiles(urls: logurls, method: method)
                }
            case .failure(let error):
                Logger.app.error("Failed to find url \(error.localizedDescription)")
            }
        }
        
        controller.dismiss(animated: true)
    }
    
    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true)
    }
    
    func importLargeNumberOfLogs(urls: [URL], method: FlightLogOrganizer.LogSelectionMethod) {
        let importAll = UIAlertAction(title: "Import All", style: .default) {
            action in
            self.logFileOrganizer.importAndAddRecordsForFiles(urls: urls, method: method)
        }
        let settings = UIAlertAction(title: "Edit Import Method", style: .default) {
            action in
            let storyboard : UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
            let vc = storyboard.instantiateViewController(identifier: "appSettingsViewController")
            vc.modalPresentationStyle = .fullScreen
            self.present(vc, animated: true)
        }
        let cancel = UIAlertAction(title: "Abort", style: .cancel) {
            action in
            //
        }
        let alert = UIAlertController(title: "Large Number of Files",
                                      message: "There is a large number of files to import (\(urls.count)). This may take a while. Please confirm before proceeding?", preferredStyle: .alert)
        alert.addAction(importAll)
        alert.addAction(settings)
        alert.addAction(cancel)
        self.present(alert, animated: true)
    }

}

