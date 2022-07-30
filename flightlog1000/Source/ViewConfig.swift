//
//  ViewConfig.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 29/07/2022.
//

import Foundation
import UIKit

struct ViewConfig {
    private init() {}
    
    static let shared : ViewConfig = ViewConfig()
    
    var titleAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.boldSystemFont(ofSize: 14.0)]
    var cellAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize: 14.0)]

}
