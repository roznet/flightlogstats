//
//  TripsTabBarController.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 28/07/2022.
//

import UIKit

class StatsTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let calendar = self.viewControllers?[1] as? StatsTripsViewController {
            calendar.aggregation = .months
        }
    }
    
}
