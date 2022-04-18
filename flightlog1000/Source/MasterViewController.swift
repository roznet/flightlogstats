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

class MasterViewController: UITableViewController, UIDocumentPickerDelegate {

    var logList : FlightLogList? = nil
    var logFileOrganizer = LogFileOrganizer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        let addButton = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(addLog(button:)))
        let editButton = UIBarButtonItem(image: UIImage(systemName: "pencil"), style: .plain, target: self, action: #selector(editLogList(button:)))
        self.navigationItem.leftBarButtonItem = addButton
        self.navigationItem.rightBarButtonItem = editButton
        self.logFileOrganizer.flightLogListFromLocal(){
            logList in
            self.logList = logList
            self.logFileOrganizer.syncCloud(with: logList)
        }

    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.buildList()
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let list = self.logList {
            return list.flightLogs.count
        }else{
            return 0
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let list = self.logList,
           let log = list.flightLogs[safe: indexPath.row] {
            if let cell = GCCellGrid(tableView) {
                cell.setup(forRows: 1, andCols: 1)
                cell.label(forRow: 0, andCol: 0).text = log.name
                return cell
            }
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        return cell
    }

    //MARK: - build list functionality
    
    func buildList() {
        self.logFileOrganizer.flightLogListFromLocal(){
            logList in
            self.logList = logList
        }
    }

    //MARK: - add functionality
    
    @objc func addLog(button : UIBarButtonItem){
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        documentPicker.delegate = self
        present(documentPicker, animated: true)
    }

    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        //FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")
        self.logFileOrganizer.copyMissingToLocal(urls: urls)
        
        controller.dismiss(animated: true)
    }
    
    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        print( "cancelled")
        controller.dismiss(animated: true)
    }
    
    //MARK: - Edit functionality
    @objc func editLogList(button : UIBarButtonItem){
        
    }
    

}

