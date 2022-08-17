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
    
    var defaultSubFont : UIFont = UIFont(name: "AvenirNext-Medium", size: 12.0)!
    var defaultBodyFont : UIFont = UIFont(name: "AvenirNext-Medium", size: 14.0)!
    var defaultHeadlineFont : UIFont = UIFont(name: "AvenirNext-Bold", size: 14.0)!
    var defaultTitleFont : UIFont = UIFont(name: "AvenirNext-Bold", size: 17.0)!
    var defaultTextEntryFont : UIFont = UIFont(name: "AvenirNext-Medium", size: 20.0)!
    
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
                .font:self.defaultHeadlineFont,
                .foregroundColor: UIColor.label
                    
            ]
            self.cellAttributes = [
                //.font:UIFont(descriptor: fontDesc, size: 0.0)
                .font:self.defaultBodyFont,
                .foregroundColor: UIColor.label
            ]
        }
    }
    
    var cellAttributes : [NSAttributedString.Key:Any] = [:]
    var titleAttributes : [NSAttributedString.Key:Any] = [:]

    var progressAttributes : [NSAttributedString.Key:Any] { return self.cellAttributes }
}
