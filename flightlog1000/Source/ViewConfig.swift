//
//  ViewConfig.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 29/07/2022.
//

import Foundation
import UIKit

class ViewConfig {
    private init() {}
    
    static let shared : ViewConfig = ViewConfig()
    static let fontFamily : String = "Avenir Next"//"Verdana"//

    var dynamicFont : Bool = false
    func setDefaultAttributes() {
        //print( UIFont.familyNames)
        //UILabel.appearance().font = UIFont(name: "Avenir", size: 14.0)!
        if self.dynamicFont {
            let headlineFontDesc = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline)
                .withFamily(ViewConfig.fontFamily)
            let bodyFontDesc = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
                .withFamily(ViewConfig.fontFamily)
            //.addingAttributes([.traits:[UIFontDescriptor.TraitKey.weight: UIFont.Weight.medium]])
            
            self.titleAttributes = [
                .font:UIFont(descriptor: headlineFontDesc, size: 0.0)
            ]
            self.cellAttributes = [
                .font:UIFont(descriptor: bodyFontDesc, size: 0.0)
            ]
        }else{
            
            self.titleAttributes = [
                .font:UIFont(name: "AvenirNext-Bold", size: 14.0)!
            ]
            self.cellAttributes = [
                //.font:UIFont(descriptor: fontDesc, size: 0.0)
                .font:UIFont(name: "AvenirNext-Medium", size: 14.0)!
            ]
        }
    }
    
    var cellAttributes : [NSAttributedString.Key:Any] = [:]
    var titleAttributes : [NSAttributedString.Key:Any] = [:]

}
