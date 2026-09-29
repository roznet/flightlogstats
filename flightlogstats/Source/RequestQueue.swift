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
        var progress : ProgressReport? = nil
        /// progress to report when this item is done
        var pct : ProgressReport.State = .complete
        
        init(flightLogFileRecord: FlightLogFileRecord, viewController: UIViewController, force: Bool = false) {
            self.flightLogFileRecord = flightLogFileRecord
            self.viewController = viewController
            self.force = force
        }
        
        private var flystoStatus : FlightFlyStoRecord.Status  { return self.flightLogFileRecord.flystoStatus }
       
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
            
            let doFlySto = flySto && (force || self.flystoStatus != .uploaded)
            var started = false
            if let url = self.flightLogFileRecord.url {
                if doFlySto {
                    Logger.ui.info("Starting flySto upload ")
                    let flyStoRequest = FlyStoUploadRequest(viewController: viewController, url: url)
                    started = true
                    flyStoRequest.execute() {
                        status,req in
                        AppDelegate.worker.async {
                            self.progress?.update(state: self.pct, message: .uploadingFiles)
                            self.flightLogFileRecord.flyStoUploadCompletion(status: status, request: req)
                            NotificationCenter.default.post(name: .flightLogViewModelUploadFinished, object: self)
                            self.flightLogFileRecord.saveContext()
                        }
                    }
                }
            }
            if !started {
                self.progress?.update(state: self.pct)
            }
        }
        
    }
   
    let operationQueue = OperationQueue()
    
    func add(record : FlightLogFileRecord, 
             viewController : UIViewController,
             force : Bool = false,
             progress : ProgressReport? = nil,
             completion : @escaping () -> Void = {}){
        let item = Item(flightLogFileRecord: record, viewController: viewController, force: force)
        self.operationQueue.addOperation(item)
        item.progress = progress
        item.pct = .complete
        self.operationQueue.addBarrierBlock {
            progress?.update(state: .complete)
            completion()
        }
    }

    func add(records : [FlightLogFileRecord], 
             viewController : UIViewController,
             force : Bool = false,
             progress : ProgressReport? = nil,
             completion : @escaping () -> Void = {}){
        let n : Double = Double(records.count)
        for (idx,record) in records.enumerated() {
            let item = Item(flightLogFileRecord: record, viewController: viewController, force: force)
            item.progress = progress
            let i = Double(idx)
            if idx < records.count - 1 {
                item.pct = .progressing((i + 1.0) / n)
            }else{
                item.pct = .complete
            }
            
            self.operationQueue.addOperation(item)
        }
        self.operationQueue.addBarrierBlock {
            progress?.update(state: .complete)
            completion()
        }
    }

    


    static let shared = RequestQueue()
    
}
