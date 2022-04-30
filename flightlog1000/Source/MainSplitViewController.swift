//
//  PrimarySplitViewController.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 30/04/2022.
//

import Foundation
import UIKit

class MainSplitViewController : UISplitViewController,UISplitViewControllerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()
        self.delegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        FlightLogOrganizer.shared.syncCloud()
        NotificationCenter.default.addObserver(forName: .localFileListChanged, object: nil, queue: nil){
            _ in
            FlightLogOrganizer.shared.syncCloud()
        }

    }
    
}
