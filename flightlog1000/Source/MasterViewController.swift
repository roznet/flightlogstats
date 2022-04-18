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
    var destFolder : URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        let addButton = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(addLog(button:)))
        let editButton = UIBarButtonItem(image: UIImage(systemName: "pencil"), style: .plain, target: self, action: #selector(editLogList(button:)))
        self.navigationItem.leftBarButtonItem = addButton
        self.navigationItem.rightBarButtonItem = editButton
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.buildList()
        self.syncCloud()
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
        FlightLog.search(in: [self.destFolder]){
            logs in
            self.logList = FlightLogList(logs: logs)
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
    }
    
    var query : NSMetadataQuery? = nil
    
    func syncCloud() {
        // look in cloud what we are missing locally
        if self.query != nil {
            self.query?.stop()
        }
        if let cloud = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents") {
            self.query = NSMetadataQuery()
            if let query = self.query {
                NotificationCenter.default.addObserver(self, selector: #selector(didFinishGathering), name: .NSMetadataQueryDidFinishGathering, object: nil)
                
                query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
                query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemPathKey)
                query.start()
            }
        }

    }

    @objc func didFinishGathering() {
        if let query = self.query {
            let names = query.results.map{($0 as? NSMetadataItem)?.value(forAttribute: NSMetadataItemURLKey)}
            print("Count: ", query.resultCount, "names: ", names) // Expected
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
        let destFolder = self.destFolder
        
        FlightLog.search(in: urls ){
            logs in
            var localLogs : [FlightLog] = []
            for log in logs {
                let file = log.url
                let dest = destFolder.appendingPathComponent(file.lastPathComponent)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    do {
                        try FileManager.default.copyItem(at: file, to: dest)
                        RZSLog.info("copied \(file.lastPathComponent) to \(dest)")
                    } catch {
                        RZSLog.error("failed to copy \(file.lastPathComponent) to \(dest)")
                    }
                    
                }else{
                    RZSLog.info("Already copied \(file.lastPathComponent)")
                }
                localLogs.append(FlightLog(url: file))
                
            }
            self.logList = FlightLogList(logs: localLogs)
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }

        }
        
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

