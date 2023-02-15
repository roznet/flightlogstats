//
//  AircraftTableViewCell.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 15/02/2023.
//

import UIKit
import RZUtils
import RZUtilsSwift

class AircraftTableViewCell: UITableViewCell {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }
    
    @IBOutlet weak var airframeLabel: UILabel!
    @IBOutlet weak var identifierLabel: UILabel!
    
    @IBOutlet weak var distanceMeasurementView: MeasurementView!
    @IBOutlet weak var timeMeasurementView: MeasurementView!
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        
        // Configure the view for the selected state
    }
    var displayContext = DisplayContext()
    
    func update(aircraft : AircraftRecord, trip : Trip?) {
        let titleAttribute = ViewConfig.shared.titleAttributes
        let cellAttribute = ViewConfig.shared.cellAttributes
        
        self.identifierLabel.attributedText = NSAttributedString(string: aircraft.aircraftIdentifier, attributes: titleAttribute)
        self.airframeLabel.attributedText = NSAttributedString(string: aircraft.airframeName, attributes: cellAttribute)
        
        if let trip = trip {
            let distance = trip.measurement(field: .Distance)
            let last = trip.measurement(field: .FuelEnd)
            let time = trip.measurement(field: .Moving)
            
            let geometry = RZNumberWithUnitGeometry()
            geometry.defaultUnitAttribute = ViewConfig.shared.cellAttributes
            geometry.defaultNumberAttribute = ViewConfig.shared.cellAttributes
            geometry.numberAlignment = .decimalSeparator
            geometry.unitAlignment = .left
            geometry.alignment = .center
            
            let config : [Trip.Field: MeasurementView] = [
                .Distance : distanceMeasurementView,
                .Moving : timeMeasurementView
            ]
            var measurements : [Trip.Field:DisplayedValue] = [:]
            for (field,_) in config {
                if let m = trip.measurement(field: field) {
                    let dv = self.displayContext.displayedValue(field: field.equivalentLogField, measurement: m)
                    dv.adjust(geometry: geometry)
                    measurements[field] = dv
                }
                for (field,measurementView) in config {
                    if let dv = measurements[field] {
                        dv.setup(measurementView: measurementView, geometry: geometry)
                    }
                }
            }
        }
    }
}
