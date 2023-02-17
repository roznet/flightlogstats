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
    
    @IBOutlet weak var lastRouteLabel: UILabel!
    @IBOutlet weak var lastFlightLabel: UILabel!
    @IBOutlet weak var fuelLabel: UILabel!
    @IBOutlet weak var distanceLabel: UILabel!
    @IBOutlet weak var timeLabel: UILabel!
    @IBOutlet weak var flightCountLabel: UILabel!
    
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
        if let lastFlight = trip?.endingFlight {
            var date = lastFlight.guessedDate
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            if let start_time = lastFlight.start_time {
                date = start_time
            }
            if let date = date {
                self.lastFlightLabel.attributedText = NSAttributedString(string: formatter.string(from: date), attributes: cellAttribute)
            }else{
                self.lastFlightLabel.attributedText = NSAttributedString(string: "", attributes: cellAttribute)
            }
            if let airport = lastFlight.flightSummary?.endAirport?.name {
                self.lastRouteLabel.attributedText = NSAttributedString(string: airport, attributes: cellAttribute)
            }else{
                self.lastRouteLabel.attributedText = NSAttributedString(string: "", attributes: cellAttribute)
            }
        }else{
            self.lastRouteLabel.attributedText = NSAttributedString(string: "", attributes: cellAttribute)
            self.lastFlightLabel.attributedText = NSAttributedString(string: "", attributes: cellAttribute)
        }
        if let trip = trip {
            self.flightCountLabel.attributedText = NSAttributedString(string: "\(trip.count) flights",attributes: cellAttribute)
        }else{
            self.flightCountLabel.attributedText = NSAttributedString(string: "",attributes: cellAttribute)
        }
        
        let config : [Trip.Field: UILabel] = [
            .Distance : distanceLabel,
            .Moving : timeLabel,
            .FuelEnd: fuelLabel
        ]
        if let trip = trip {
            for (field,label) in config {
                if let m = trip.measurement(field: field) {
                    let dv = self.displayContext.displayedValue(field: field.equivalentLogField, measurement: m)
                    label.attributedText = NSAttributedString(string: dv.string, attributes: cellAttribute)
                }else{
                    label.attributedText = NSAttributedString(string: "", attributes: cellAttribute)
                }
            }
        }
    }
}
