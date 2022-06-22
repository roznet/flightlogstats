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
        
        // find master view
        guard
            let leftNavController = self.viewControllers.first as? UINavigationController,
            let logListController = leftNavController.viewControllers.first as? LogListTableViewController,
            let rightTabbarController = self.viewControllers.last as? LogDetailTabBarController
        else { fatalError() }
        
        logListController.delegate = rightTabbarController
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(forName: .localFileListChanged, object: nil, queue: nil){
            _ in
            FlightLogOrganizer.shared.syncCloud()
        }
    }
    
}
