//
//  RequestQueue.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 04/10/2023.
//

import Foundation
import UIKit
import OSLog
import RZUtils

class RequestQueue {
    class Item : Operation {
        var flightLogFileRecord : FlightLogFileRecord
        var viewController : UIViewController
        var force : Bool = false
        
        init(flightLogFileRecord: FlightLogFileRecord, viewController: UIViewController, force: Bool = false) {
            self.flightLogFileRecord = flightLogFileRecord
            self.viewController = viewController
            self.force = force
        }
        
        private var flystoStatus : FlightFlyStoRecord.Status  { return self.flightLogFileRecord.flystoStatus }
        private var savvyStatus : FlightSavvyRecord.Status { return self.flightLogFileRecord.savvyStatus }
       
        override func main() {
            guard isCancelled == false else {
                return
            }
            
            // don't bother if no network
            guard RZSystemInfo.networkAvailable() else {
                Logger.net.info("No network available, skipping uploads")
                return
            }
            
            let flySto = Settings.shared.flystoEnabled
            let savvy = Settings.shared.savvyEnabled
            if let url = self.flightLogFileRecord.url {
                if flySto && (force || self.flystoStatus != .uploaded) {
                    Logger.ui.info("Starting flySto upload ")
                    let flyStoRequest = FlyStoUploadRequest(viewController: viewController, url: url)
                    flyStoRequest.execute() {
                        status,req in
                        AppDelegate.worker.async {
                            self.flightLogFileRecord.flyStoUploadCompletion(status: status, request: req)
                            NotificationCenter.default.post(name: .flightLogViewModelUploadFinished, object: self)
                            self.flightLogFileRecord.saveContext()
                        }
                    }
                }
                if savvy && (force || self.savvyStatus != .uploaded) {
                    if let identifier = self.flightLogFileRecord.aircraftRecord?.aircraftIdentifier {
                        let savvyRequest = SavvyRequest(viewController: viewController, url: url, aircraftIdentifier: identifier)
                        savvyRequest.execute(){ status,req in
                            AppDelegate.worker.async {
                                self.flightLogFileRecord.savvyUploadCompletion(status: status, request: req)
                                NotificationCenter.default.post(name: .flightLogViewModelUploadFinished, object: self)
                                self.flightLogFileRecord.saveContext()
                            }
                        }
                    }
                }
            }
        }
        
    }
   
    let operationQueue = OperationQueue()
    
    func add(record : FlightLogFileRecord, viewController : UIViewController, force : Bool = false){
        let item = Item(flightLogFileRecord: record, viewController: viewController, force: force)
        self.operationQueue.addOperation(item)
    }
    
    static let shared = RequestQueue()
    
}
