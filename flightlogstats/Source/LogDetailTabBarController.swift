//
//  LogDetailTabBar.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 20/06/2022.
//

import UIKit
import OSLog

protocol ViewModelDelegate : AnyObject {
    func viewModelDidFinishBuilding(viewModel : FlightLogViewModel)
    func viewModelHasChanged(viewModel: FlightLogViewModel)
}

class LogDetailTabBarController: UITabBarController, LogSelectionDelegate {
    var logViewModel : FlightLogViewModel? = nil
    var progress : ProgressReport? = nil
    var progressReportOverlay : ProgressReportOverlay? = nil
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if self.progressReportOverlay == nil {
            self.progressReportOverlay = ProgressReportOverlay(viewController: self)
        }
        
        // Delay a bit so rest of the UI/list if applicable is drawn
        DispatchQueue.main.asyncAfter(deadline: .now()+0.2){
            self.selectOneIfEmpty(organizer: FlightLogOrganizer.shared)
        }
        
        NotificationCenter.default.addObserver(forName: .settingsViewControllerUpdate, object: nil, queue: nil){
            _ in
            Logger.ui.info("Update flight view model for setting change")
            
            self.logViewModel?.updateForSettings()
        }
        
        NotificationCenter.default.addObserver(forName: .ErrorOccured, object: AppDelegate.errorManager, queue: nil) {
            _ in
            if let error = AppDelegate.errorManager.popLast() {
                Logger.ui.info("Reporting error \(error.localizedDescription)")
            }else{
                Logger.ui.info("No error to report")
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }
    
    private func viewModelHasChanged(viewModel: FlightLogViewModel){
        if let viewControllers = self.viewControllers {
            for controller in viewControllers {
                if let selectionDelegate = controller as? ViewModelDelegate  {
                    selectionDelegate.viewModelHasChanged(viewModel: viewModel)
                }
            }
        }
    }
    
    //MARK: - LogSelection Delegate
    
    var logInfoIsSelected: Bool {
        return self.logViewModel != nil
    }
    
    func selectlogInfo(_ info: FlightLogFileRecord) {
        if self.progress == nil {
            self.progress = ProgressReport(message: .parsingInfo) {
                progress in
                self.progressReportOverlay?.update(for: progress)
            }
        }
        self.progressReportOverlay?.prepareOverlay(message: .parsingInfo)
        let viewModel = FlightLogViewModel(fileInfo: info, displayContext: DisplayContext(), progress: self.progress)
        self.logViewModel = viewModel
        // notifiy it change but may not be complete
        self.viewModelHasChanged(viewModel: viewModel)
        AppDelegate.worker.async {
            self.logViewModel?.build()
        }
    }
    
    func selectOneIfEmpty(organizer : FlightLogOrganizer) {
        if self.logViewModel == nil, let first = organizer.first {
            self.selectlogInfo(first)
        }
    }

}
