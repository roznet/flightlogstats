//
//  MeasurementView.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 03/12/2022.
//

import UIKit
import RZUtils
import RZUtilsSwift
import OSLog

class MeasurementView: UIView {
    enum Formatter {
        case measurement(MeasurementFormatter)
        case compound(CompoundMeasurementFormatter<Dimension>)
    }
    
    var geometry : RZNumberWithUnitGeometry { didSet { self.setNeedsDisplay(); self.setNeedsLayout() }}
    var measurement : Measurement<Dimension> { didSet { self.setNeedsDisplay(); self.setNeedsLayout() }}
    var formatter : Formatter { didSet { self.setNeedsDisplay(); self.setNeedsLayout() }}
    var attributes : [NSAttributedString.Key:Any]? { didSet { self.setNeedsDisplay(); self.setNeedsLayout() }}
    
    init(measurement : Measurement<Dimension>, formatter : MeasurementFormatter, geometry:RZNumberWithUnitGeometry){
        self.measurement = measurement
        self.formatter = Formatter.measurement(formatter)
        self.geometry = geometry
        self.attributes = nil
        super.init(frame: .zero)
    }

    init(measurement : Measurement<Dimension>, compound : CompoundMeasurementFormatter<Dimension>, geometry:RZNumberWithUnitGeometry){
        self.measurement = measurement
        self.formatter = Formatter.compound(compound)
        self.geometry = geometry
        self.attributes = nil
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        self.geometry = RZNumberWithUnitGeometry()
        if let nu = coder.decodeObject(forKey: "measurement") as? Measurement<Dimension> {
            self.measurement = nu
        }else{
            self.measurement = Measurement(value: 0.0, unit: UnitLength.nauticalMiles)
        }
        if let fmt = coder.decodeObject(forKey: "formatter") as? MeasurementFormatter {
            self.formatter = Formatter.measurement(fmt)
        }else{
            self.formatter = Formatter.measurement(MeasurementFormatter())
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
        switch self.formatter {
        case .measurement(let fmt):
            self.geometry.drawInRect(rect, measurement: self.measurement, formatter: fmt, numberAttribute: self.attributes)
        case .compound(let compound):
            self.geometry.drawInRect(rect, measurement: self.measurement, compound: compound, numberAttribute: self.attributes)
        }
        
    }
    


}
