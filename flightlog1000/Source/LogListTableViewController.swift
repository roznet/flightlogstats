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
    func logInfoSelected(_ info : FlightLogFileInfo)
    func selectOneIfEmpty(organizer : FlightLogOrganizer)
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
        let menuItems : [UIAction] = [
            UIAction(title: "Toggle Filter", image: UIImage(systemName: "minus.circle")){
                _ in
                self.filterEmpty = !self.filterEmpty
                self.buildList()
                self.tableView.reloadData()
            },

            UIAction(title: "Delete", image: UIImage(systemName: "minus.circle")){
                _ in
                Logger.app.info("Delete")
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

        ]
        
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
            self.buildList()
            DispatchQueue.main.async {
                self.tableView.reloadData()
                if let info = self.logInfoList.first  {
                    self.delegate?.logInfoSelected(info)
                }else{
                    self.delegate?.selectOneIfEmpty(organizer: self.logFileOrganizer)
                }
            }
        }
        NotificationCenter.default.addObserver(forName: .logFileInfoUpdated, object: nil, queue: nil){
            _ in
            self.buildList()
            DispatchQueue.main.async {
                self.tableView.reloadData()
                if let info = self.logInfoList.first {
                    self.delegate?.logInfoSelected(info)
                }else{
                    self.delegate?.selectOneIfEmpty(organizer: self.logFileOrganizer)
                }
            }
        }
        /*
        NotificationCenter.default.addObserver(forName: .kProgressUpdate, object: nil, queue: nil){
            notification in
            if let progress = notification.object as? ProgressReport {
                self.update(for: progress)
            }else{
                Logger.app.error("invalid notification \(notification)")
            }
        }
         */
        self.buildList()
    }
    

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.logInfoList.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
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
            
            /*
            if let cell = GCCellGrid(tableView) {
                cell.setup(forRows: 1, andCols: 1)
                cell.label(forRow: 0, andCol: 0).text = log.name
                return cell
            }*/
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 100.0
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let info = self.flightInfo(at: indexPath){
            self.ensureDelegate()
            self.delegate?.logInfoSelected(info)
            self.userInterfaceModeManager?.userInterfaceMode = .detail
            self.updateButtons()
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
                }
            }
        }else{
            self.fullLogInfoList = self.logFileOrganizer.flightLogFileInfos
            self.updateSearchedList()
            self.tableView.reloadData()
            self.delegate?.selectOneIfEmpty(organizer: self.logFileOrganizer)
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
        print( "cancelled")
        controller.dismiss(animated: true)
    }

}

