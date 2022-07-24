//
//  RZNumberWithUnitView.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 24/07/2022.
//

import UIKit
import RZUtils
import RZUtilsSwift
import OSLog

class RZNumberWithUnitView: UIView {
    var geometry : RZNumberWithUnitGeometry { didSet { self.setNeedsDisplay(); self.setNeedsLayout() }}
    var numberWithUnit : GCNumberWithUnit { didSet { self.setNeedsDisplay(); self.setNeedsLayout() }}
    
    init(numberWithUnit : GCNumberWithUnit, geometry:RZNumberWithUnitGeometry){
        self.numberWithUnit = numberWithUnit
        self.geometry = geometry
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        self.geometry = RZNumberWithUnitGeometry()
        if let nu = coder.decodeObject(forKey: "numberWithUnit") as? GCNumberWithUnit {
            self.numberWithUnit = nu
        }else{
            self.numberWithUnit = GCNumberWithUnit()
        }
        super.init(coder: coder)
    }
    
    override var intrinsicContentSize: CGSize {
        return self.geometry.totalSize
    }
    
    // Only override draw() if you perform custom drawing.
    // An empty implementation adversely affects performance during animation.
    override func draw(_ rect: CGRect) {
        // Drawing code
        self.geometry.drawInRect(rect, numberWithUnit: self.numberWithUnit)
    }
    

}
