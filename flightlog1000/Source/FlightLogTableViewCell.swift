//
//  FlightLogTableViewCell.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 30/04/2022.
//

import UIKit

class FlightLogTableViewCell: UITableViewCell {
    var flightLogFileInfo : FlightLogFileInfo? = nil
    var displayContext : DisplayContext = DisplayContext()
    
    @IBOutlet weak var flightTime: UILabel!
    @IBOutlet weak var totalTime: UILabel!
    @IBOutlet weak var route: UILabel!
    @IBOutlet weak var airports: UILabel!
    @IBOutlet weak var fuel: UILabel!
    
    @IBOutlet weak var distance: UILabel!
    @IBOutlet weak var date: UILabel!
    @IBOutlet weak var fileName: UILabel!
    
    func update(with info: FlightLogFileInfo){
        self.fileName.text = info.log_file_name
        self.flightLogFileInfo = info
        if let flightSummary = info.flightSummary {
            self.totalTime.text = self.displayContext.formatDecimal(timeRange: flightSummary.hobbs)
            if let flying = flightSummary.flying {
                self.flightTime.text = self.displayContext.formatDecimal(timeRange: flying)
            }else{
                self.flightTime.text = "0.0"
            }
            self.fuel.text = self.displayContext.formatValue(gallon: flightSummary.fuelUsed.total)
            self.route.text = self.displayContext.format(route: flightSummary.route)
            self.distance.text = self.displayContext.formatValue(distanceMeter: flightSummary.distance)
            var airports : [String] = []
            if let from = flightSummary.startAirport {
                airports.append(from.icao)
            }
            if let to = flightSummary.endAirport {
                airports.append(to.icao)
            }
            self.airports.text = airports.joined(separator: "-")
        }else{
            self.totalTime.text = "??"
            self.flightTime.text = nil
            self.fuel.text = nil
            self.route.text = nil
            self.distance.text = nil
            self.airports.text = nil

        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
