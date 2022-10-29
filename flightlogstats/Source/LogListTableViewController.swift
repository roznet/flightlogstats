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
    func selectlogInfo(_ info : FlightLogFileInfo)
    var logInfoIsSelected : Bool { get }
}

class LogListTableViewController: UITableViewController, UIDocumentPickerDelegate, UISearchResultsUpdating {

    var logInfoList : [FlightLogFileInfo] = []
    var fullLogInfoList : [FlightLogFileInfo] = []
    
    var logFileOrganizer = FlightLogOrganizer.shared
    
    weak var delegate : LogSelectionDelegate? = nil
    weak var userInterfaceModeManager : UserInterfaceModeManager? = nil
    
    var searchController : UISearchController = UISearchController()
    var isSearchBarEmpty : Bool { return searchController.searchBar.text?.isEmpty ?? true }
    
    var filterEmpty = true
    
    func flightInfo(at indexPath : IndexPath) -> FlightLogFileInfo? {
        return self.logInfoList[indexPath.row]
    }
    
    // for iphone, or start in list more delegate may not be instantiated yet
    func ensureDelegate(){
        if self.delegate == nil {
            if let detailViewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "LogDetailTabBarController") as? LogDetailTabBarController {
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
            UIAction(title: "Force Refresh", image: UIImage(systemName: "minus.circle")){
                _ in
                self.buildList()
                self.tableView.reloadData()
            },
            UIAction(title: self.filterEmpty ? "Show non-flights" : "Show flights only", image: UIImage(systemName: "minus.circle")){
                _ in
                self.filterEmpty = !self.filterEmpty
                self.buildList()
                self.tableView.reloadData()
                self.updateButtons()
            },
            ]
        if FlyStoRequests.hasCredential {
            menuItems.append(UIAction(title: "Logout of FlySto", image: UIImage(systemName: "minus.circle")) {
                _ in
                FlyStoRequests.clearCredential()
                self.updateButtons()
            })
        }
#if DEBUG
        menuItems.append(contentsOf: [
            UIAction(title: "Delete last", image: UIImage(systemName: "minus.circle")){
                _ in
                if let info = self.logFileOrganizer.firstNonEmpty, let log_file_name = info.log_file_name {
                    Logger.ui.info("Deleting \(log_file_name)")
                    self.logFileOrganizer.delete(info: info)
                }
            },
            UIAction(title: "Rebuild Info", image: UIImage(systemName: "plus.circle")){
                _ in
                Logger.app.info("Rebuild info")
                self.logFileOrganizer.updateInfo(count: 1000, force: true)
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
        
        self.navigationItem.leftBarButtonItem = addButton
        
        if self.userInterfaceModeManager?.userInterfaceMode == .stats {
            let planeButton = UIBarButtonItem(image: UIImage(systemName: "airplane.circle"), style: .plain, target: self, action: #selector(sum(button:)))
            self.navigationItem.rightBarButtonItems = [moreFunctionButton, planeButton]
        }else{ // this include the case userInterfaceModeManager is nil
            let sumButton = UIBarButtonItem(image: UIImage(systemName: "sum"), style: .plain, target: self, action: #selector(sum(button:)))
            self.navigationItem.rightBarButtonItems = [moreFunctionButton, sumButton]
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
        case statistics = 0, flights
        
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
            return self.logInfoList.count
        case .statistics:
            return 1
        case .none:
            return 0
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch TableSection(indexPath: indexPath) {
        case .flights:
            let cell = tableView.dequeueReusableCell(withIdentifier: "flightlogcell", for: indexPath)
            if let cell = cell as? LogListTableViewCell,
               let info = self.flightInfo(at: indexPath) {
                cell.update(minimum: info)
                AppDelegate.worker.async {
                    let _ = info.flightSummary
                    DispatchQueue.main.async {
                        cell.update(with: info)
                    }
                }
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
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch TableSection(indexPath: indexPath) {
        case .flights:
            if let info = self.flightInfo(at: indexPath){
                self.ensureDelegate()
                self.delegate?.selectlogInfo(info)
                self.userInterfaceModeManager?.userInterfaceMode = .detail
                self.updateButtons()
            }
        case .statistics:
            self.userInterfaceModeManager?.userInterfaceMode = .stats
            self.updateButtons()
        case .none:
            return
        }
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let logCell = (cell as? LogListTableViewCell) {
            NotificationCenter.default.addObserver(forName: .logFileInfoUpdated, object: nil, queue: nil){
                notification in
                if let info = (notification.object as? FlightLogFileInfo) {
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
    
    
    //MARK: - build list functionality
    
    func buildList() {
        if self.filterEmpty {
            AppDelegate.worker.async {
                self.fullLogInfoList = self.logFileOrganizer.nonEmptyLogFileInfos
                DispatchQueue.main.async {
                    self.updateSearchedList()
                    self.tableView.reloadData()
                    self.ensureOneDetailDisplayed()
                }
            }
        }else{
            self.fullLogInfoList = self.logFileOrganizer.flightLogFileInfos
            self.updateSearchedList()
            self.tableView.reloadData()
            self.ensureOneDetailDisplayed()
        }
    }

    private func ensureOneDetailDisplayed() {
        if let delegate = self.delegate, !delegate.logInfoIsSelected {
            if let info = self.logInfoList.first  {
                delegate.selectlogInfo(info)
            }else if let info = self.logFileOrganizer.first {
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
    
    @objc func addLog(button : UIBarButtonItem){
        // mac should select files, ios just import folder
#if targetEnvironment(macCatalyst)
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [
            .commaSeparatedText, .folder
        ])
        documentPicker.allowsMultipleSelection = true
#else
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [
            .folder
        ])
#endif
        documentPicker.delegate = self
        present(documentPicker, animated: true)
    }

    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.progressReportOverlay?.prepareOverlay(message: .addingFiles)
        self.logFileOrganizer.copyMissingToLocal(urls: urls)
        
        controller.dismiss(animated: true)
    }
    
    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true)
    }

}

