//
//  PrimarySplitViewController.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 30/04/2022.
//

import Foundation
import UIKit

enum UserInterfaceMode {
    case stats
    case detail
}

protocol UserInterfaceModeManager : AnyObject {
    var userInterfaceMode : UserInterfaceMode { get set }
}

class MainSplitViewController : UISplitViewController,UISplitViewControllerDelegate,UserInterfaceModeManager {

    var logListController : LogListTableViewController? = nil
    var logDetailTabBarController : LogTabBarController? = nil
    var statsTabBarController : StatsTabBarController? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.delegate = self
        
        // find master view
        guard
            let leftNavController = self.viewControllers.first as? UINavigationController,
            let logListController = leftNavController.viewControllers.first as? LogListTableViewController,
            let rightTabbarController = self.viewControllers.last as? LogTabBarController
        else { fatalError() }
        
        self.logListController = logListController
        self.logDetailTabBarController = rightTabbarController
        
        self.logListController?.delegate = rightTabbarController
        self.logListController?.userInterfaceModeManager = self
        
        
    }
    
#if DEBUG
    /// Development: `-FLSImportFolder <path>` opens the import sheet on a folder, and
    /// `-FLSShowUploads YES` the Uploads screen, without the document picker.
    private var debugLaunchDone = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !self.debugLaunchDone, let list = self.logListController else { return }
        self.debugLaunchDone = true
        if let path = UserDefaults.standard.string(forKey: "FLSImportFolder") {
            list.documentPicker(UIDocumentPickerViewController(forOpeningContentTypes: [.folder]), didPickDocumentsAt: [URL(fileURLWithPath: path)])
        }else if UserDefaults.standard.bool(forKey: "FLSShowUploads") {
            self.present(UploadsViewController(), animated: true)
        }
    }
#endif
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

    }
    
    var userInterfaceMode : UserInterfaceMode = .detail {
        didSet {
            switch userInterfaceMode {
            case .detail:
                self.displayDetail()
            case .stats:
                self.displayStats()
            }
        }
    }
    
    func displayStats() {
        if self.statsTabBarController == nil {
            let storyBoard = UIStoryboard(name: "Main", bundle: Bundle.main)
            guard
                  let controller = storyBoard.instantiateViewController(withIdentifier: "statsTabBarController") as? StatsTabBarController
            else {
                return
            }
            self.statsTabBarController = controller
        }
        
        if let controller = self.statsTabBarController {
            self.showDetailViewController(controller, sender: self)
        }
    }
    
    func displayDetail() {
        if let detail = self.logDetailTabBarController {
            self.showDetailViewController(detail, sender: self)
        }
    }
    
}
