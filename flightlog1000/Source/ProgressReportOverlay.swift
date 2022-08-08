//
//  ProgressReportOverlay.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 07/08/2022.
//

import Foundation
import UIKit

struct ProgressReportOverlay {
    let progressReportViewController : ProgressReportViewController
    let viewController : UIViewController
    
    var isHidden : Bool { return self.progressReportViewController.view.isHidden }

    init(viewController: UIViewController){
        let storyBoard = UIStoryboard(name: "Main", bundle: nil)
        guard let progressReport = storyBoard.instantiateViewController(withIdentifier: "ProgressReport") as? ProgressReportViewController else {
            fatalError("Failed to initalise storyboard")
        }
        self.progressReportViewController = progressReport
        self.progressReportViewController.view.isHidden = true
        self.viewController = viewController
    }
    
    func displayOverlay() {
        viewController.view.addSubview(progressReportViewController.view)
        viewController.view.bringSubviewToFront(progressReportViewController.view)
        progressReportViewController.view.isHidden = false
        var frame = viewController.view.frame
        if let tabBar = (viewController as? UITabBarController)?.tabBar {
            frame.origin.y = frame.size.height - 60.0 - tabBar.frame.height
        }else{
            frame.origin.y = frame.size.height - 60.0
        }
        frame.origin.x = 0
        
        frame.size.height = 60.0
        progressReportViewController.view.frame = frame
    }
    
    func removeOverlay(delay : Double = 1.0){
        DispatchQueue.main.asyncAfter(deadline: .now()+delay) {
            progressReportViewController.view.isHidden = true
            progressReportViewController.view.removeFromSuperview()
        }
    }
    
    func prepareOverlay(message : ProgressReport.Message){
        self.displayOverlay()
        self.progressReportViewController.reset(with: message)
    }
    
    func update(for report : ProgressReport ){
        DispatchQueue.main.async {
            if report.state != .complete && self.isHidden {
                self.displayOverlay()
            }
            if progressReportViewController.update(for: report) {
                self.removeOverlay(delay: report.fastProcessing ? 0.1 : 1.0)
            }
        }
    }
}
