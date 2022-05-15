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
}

class MasterViewController: UITableViewController, UIDocumentPickerDelegate {

    var logList : FlightLogFileList? = nil
    var logFileOrganizer = FlightLogOrganizer.shared
    
    weak var delegate : LogSelectionDelegate? = nil
    
    func moreFunctionMenu() -> UIMenu {
        let menuItems : [UIAction] = [
            UIAction(title: "Delete", image: UIImage(systemName: "minus.circle")){
                _ in
                Logger.app.info("Delete")
            },
            UIAction(title: "Reset All", image: UIImage(systemName: "minus.circle")){
                _ in
                Logger.app.info("Reset All")
                self.logFileOrganizer.deleteAndResetAll()
            }
        ]
        
        return UIMenu( options: .displayInline, children: menuItems)
        
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
        NotificationCenter.default.addObserver(forName: .localFileListChanged, object: nil, queue: nil){
            _ in
            self.buildList()
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
        NotificationCenter.default.addObserver(forName: .logFileInfoUpdated, object: nil, queue: nil){
            _ in
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
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
        if let cell = cell as? FlightLogTableViewCell,
           let info = self.flightInfo(at: indexPath) {
            
            cell.update(with: info)
            
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
            if self.delegate == nil,
               let detailViewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "LogDetailViewController") as? LogDetailViewController {
                detailViewController.logFileOrganizer = self.logFileOrganizer
                self.delegate = detailViewController
                self.delegate?.logInfoSelected(info)
                splitViewController?.showDetailViewController(detailViewController, sender: self)
            }else{
                self.delegate?.logInfoSelected(info)
                if let detailViewController = delegate as? LogDetailViewController {
                    detailViewController.logFileOrganizer = self.logFileOrganizer
                    splitViewController?.showDetailViewController(detailViewController, sender: nil)
                }
            }
        }
    }
    //MARK: - build list functionality
    
    func buildList() {
        self.logList = self.logFileOrganizer.flightLogFileList
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

