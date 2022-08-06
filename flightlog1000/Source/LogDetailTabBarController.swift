//
//  LogDetailTabBar.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 20/06/2022.
//

import UIKit

protocol ViewModelDelegate : AnyObject {
    func viewModelDidFinishBuilding(viewModel : FlightLogViewModel)
    func viewModelHasChanged(viewModel: FlightLogViewModel)
}

class LogDetailTabBarController: UITabBarController, LogSelectionDelegate {
    var logViewModel : FlightLogViewModel? = nil
    
    private func viewModelHasChanged(viewModel: FlightLogViewModel){
        if let viewControllers = self.viewControllers {
            for controller in viewControllers {
                if let selectionDelegate = controller as? ViewModelDelegate  {
                    selectionDelegate.viewModelHasChanged(viewModel: viewModel)
                }
            }
        }
    }
    
    func logInfoSelected(_ info: FlightLogFileInfo) {
        let viewModel = FlightLogViewModel(fileInfo: info, displayContext: DisplayContext())
        self.logViewModel = viewModel
        // notifiy it change but may not be complete
        self.viewModelHasChanged(viewModel: viewModel)
        AppDelegate.worker.async {
            self.logViewModel?.build()
        }
    }
    
    func selectOneIfEmpty(organizer : FlightLogOrganizer) {
        if self.logViewModel == nil, let first = organizer.first {
            self.logInfoSelected(first)
        }
    }

}
