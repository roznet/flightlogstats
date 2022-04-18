//
//  ViewController.swift
//  flightlog1000
//
//  Created by Brice Rosenzweig on 18/04/2022.
//

import UIKit
import RZUtils
import RZUtilsTouch
import UniformTypeIdentifiers

class MasterViewController: UITableViewController, UIDocumentPickerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        let addButton = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(addLog(button:)))
        let editButton = UIBarButtonItem(image: UIImage(systemName: "pencil"), style: .plain, target: self, action: #selector(editLogList(button:)))
        self.navigationItem.leftBarButtonItem = addButton
        self.navigationItem.rightBarButtonItem = editButton
        
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = GCCellGrid(tableView) {
            cell.setup(forRows: 1, andCols: 1)
            cell.label(forRow: 0, andCol: 0).text = "Hello"
            return cell
        }else{
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            return cell
        }
    }

    
    @objc func addLog(button : UIBarButtonItem){
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        documentPicker.delegate = self
        present(documentPicker, animated: true)
        
    }
    
    @objc func editLogList(button : UIBarButtonItem){
        
    }
    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        print( "picked")
        controller.dismiss(animated: true)
    }
    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        print( "cancelled")
        controller.dismiss(animated: true)
    }
}

