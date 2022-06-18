//
//  FlightLogTableViewCell.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 30/04/2022.
//

import UIKit

class LogListTableViewCell: UITableViewCell {
    var flightLogFileInfo : FlightLogFileInfo? = nil
    var displayContext : DisplayContext = DisplayContext()
    
    @IBOutlet weak var flightIcon: UIImageView!
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
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            if let start_time = info.start_time {
                self.date.text = formatter.string(from: start_time)
            }else{
                self.date.text = "Missing"
            }
            if let hobbs = flightSummary.hobbs {
                self.totalTime.text = self.displayContext.formatDecimal(timeRange: hobbs)
            }else{
                self.totalTime.text = nil
            }
            if let flying = flightSummary.flying {
                self.flightTime.isHidden = false
                self.flightIcon.isHidden = false
                self.flightTime.text = self.displayContext.formatDecimal(timeRange: flying)
            }else{
                self.flightIcon.isHidden = true
                self.flightTime.isHidden = true
                
                self.flightTime.text = "0.0"
            }
            self.fuel.text = self.displayContext.formatValue(gallon: flightSummary.fuelUsed.total)
            if let endAirport = flightSummary.endAirport {
                self.route.isHidden = false
                self.route.text = self.displayContext.format(airport: endAirport, icao: false)
            }else{
                self.route.isHidden = true
            }
            self.distance.text = self.displayContext.formatValue(distance: flightSummary.distance)
            var airports : [String] = []
            if let from = flightSummary.startAirport {
                airports.append(from.icao)
            }
            if let to = flightSummary.endAirport {
                airports.append(to.icao)
            }
            self.airports.text = airports.joined(separator: "-")
        }else{
            self.date.text = "Empty"
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
