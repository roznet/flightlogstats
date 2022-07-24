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

class LogListTableViewController: UITableViewController, UIDocumentPickerDelegate {

    var logList : FlightLogFileList? = nil
    var logFileOrganizer = FlightLogOrganizer.shared
    
    var progressReportViewController : ProgressReportViewController? = nil
    
    weak var delegate : LogSelectionDelegate? = nil
    var filterEmpty = true
    
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
                self.displayOverlay()
            }

        ]
        
        return UIMenu( options: .displayInline, children: menuItems)
        
    }
    
    func displayOverlay() {
        if self.progressReportViewController == nil {
            let storyBoard = UIStoryboard(name: "Main", bundle: nil)
            if let progressReport = storyBoard.instantiateViewController(withIdentifier: "ProgressReport") as? ProgressReportViewController {
                self.progressReportViewController = progressReport
            }
        }
        
        if let progressReport = self.progressReportViewController,
           let navigationController = self.navigationController {
            
            navigationController.view.addSubview(progressReport.view)
            navigationController.view.bringSubviewToFront(progressReport.view)
            progressReport.view.isHidden = false
            var frame = navigationController.view.frame
            frame.origin.x = 0
            frame.origin.y = frame.size.height - 60.0
            frame.size.height = 60.0
            progressReport.view.frame = frame
        }
    }
    
    func removeOverlay(delay : Double = 2.0){
        DispatchQueue.main.asyncAfter(deadline: .now()+delay) {
            if let progressReportViewController = self.progressReportViewController {
                progressReportViewController.view.removeFromSuperview()
                self.progressReportViewController = nil
            }
        }
    }
    
    func prepareOverlay(message : String){
        if self.progressReportViewController == nil {
            self.displayOverlay()
        }
        self.progressReportViewController?.statusLabel.text = message
        self.progressReportViewController?.progressBar.setProgress(0, animated: false)
        
    }
    
    func update(for report : ProgressReport ){
        DispatchQueue.main.async {
            if report.state != .complete && self.progressReportViewController == nil {
                self.displayOverlay()
            }
            if let controller = self.progressReportViewController {
                if controller.update(for: report) {
                    self.removeOverlay()
                }
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        let addButton = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(addLog(button:)))
        let moreFunctionButton = UIBarButtonItem(title: "More", image: UIImage(systemName: "ellipsis.circle"), menu: self.moreFunctionMenu())
        self.navigationItem.leftBarButtonItem = addButton
        self.navigationItem.rightBarButtonItem = moreFunctionButton
        
        self.tableView.estimatedRowHeight = 100
        self.tableView.rowHeight = UITableView.automaticDimension
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.logFileOrganizer.ensureProgressReport() {
            progress in
            self.update(for: progress)
        }
        NotificationCenter.default.addObserver(forName: .localFileListChanged, object: nil, queue: nil){
            _ in
            self.buildList()
            DispatchQueue.main.async {
                self.tableView.reloadData()
                if let first = self.logList?.first,let info = self.logFileOrganizer[first.name]  {
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
                if let first = self.logList?.first,
                   let info = self.logFileOrganizer[first.name] {
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
        if let list = self.logList {
            return list.flightLogFiles.count
        }else{
            return 0
        }
    }
    
    func flightInfo(at indexPath : IndexPath) -> FlightLogFileInfo? {
        guard let list = self.logList else { return nil }
        return FlightLogOrganizer.shared[list.flightLogFiles[ indexPath.row].name]
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "flightlogcell", for: indexPath)
        if let cell = cell as? LogListTableViewCell,
           let info = self.flightInfo(at: indexPath) {
            
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
        return 120.0
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let info = self.flightInfo(at: indexPath){
            if self.delegate == nil,
               let detailViewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "LogDetailTabBarController") as? LogDetailTabBarController {
                self.delegate = detailViewController
                self.delegate?.logInfoSelected(info)
                splitViewController?.showDetailViewController(detailViewController, sender: self)
            }else{
                self.delegate?.logInfoSelected(info)
                if let detailViewController = delegate as? LogDetailTabBarController {
                    splitViewController?.showDetailViewController(detailViewController, sender: nil)
                }
            }
        }
    }
    //MARK: - build list functionality
    
    func buildList() {
        
        if self.filterEmpty {
            AppDelegate.worker.async {
                self.logList = self.logFileOrganizer.nonEmptyLogFileList
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
                DispatchQueue.main.asyncAfter(deadline: .now()+0.5){
                    if let first = self.logList?.first,
                       let info = self.logFileOrganizer[first.name] {
                        self.delegate?.logInfoSelected(info)
                    }else{
                        self.delegate?.selectOneIfEmpty(organizer: self.logFileOrganizer)
                    }
                }
            }
        }else{
            self.logList = self.logFileOrganizer.flightLogFileList
            self.tableView.reloadData()
            self.delegate?.selectOneIfEmpty(organizer: self.logFileOrganizer)
        }
    }

    //MARK: - add functionality
    
    @objc func addLog(button : UIBarButtonItem){
        // mac should select files, ios just import folder
#if targetEnvironment(macCatalyst)
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [
            .commaSeparatedText
        ])
#else
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [
            .folder
        ])
#endif
        documentPicker.delegate = self
        present(documentPicker, animated: true)
    }

    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.prepareOverlay(message: "Adding Files")
        self.logFileOrganizer.copyMissingToLocal(urls: urls)
        
        controller.dismiss(animated: true)
    }
    
    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        print( "cancelled")
        controller.dismiss(animated: true)
    }
    
    //MARK: - Edit functionality
    @objc func showMoreFunctions(button : UIBarButtonItem){
        
    }
    

}

