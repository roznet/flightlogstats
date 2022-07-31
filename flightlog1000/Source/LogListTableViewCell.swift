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
        
        let titleAttribute = ViewConfig.shared.titleAttributes
        let cellAttribute = ViewConfig.shared.cellAttributes
        
        if let flightSummary = info.flightSummary {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            if let start_time = info.start_time {
                self.date.attributedText = NSAttributedString(string: formatter.string(from: start_time), attributes: cellAttribute)
            }else{
                self.date.attributedText = NSAttributedString(string: "Missing", attributes: cellAttribute)
            }
            if let hobbs = flightSummary.hobbs {
                self.totalTime.attributedText = NSAttributedString(string: self.displayContext.formatDecimal(timeRange: hobbs), attributes: cellAttribute)
            }else{
                self.totalTime.text = nil
            }
            if let flying = flightSummary.flying {
                self.flightTime.isHidden = false
                self.flightIcon.isHidden = false
                self.flightTime.attributedText = NSAttributedString(string: self.displayContext.formatDecimal(timeRange: flying), attributes: titleAttribute)
            }else{
                self.flightIcon.isHidden = true
                self.flightTime.isHidden = true
                
                self.flightTime.attributedText = NSAttributedString(string: "", attributes: titleAttribute)
            }
            
            if let total = flightSummary.numberWithUnit(for: .FuelTotalizer),
               let used = flightSummary.numberWithUnit(for: .FuelUsed) {
                self.fuel.attributedText = NSAttributedString(string: total.value != 0.0 ? total.formatDouble() : used.formatDouble(), attributes: cellAttribute)
            }else{
                self.fuel.attributedText = NSAttributedString(string: "", attributes: cellAttribute)
            }
            
            if let endAirport = flightSummary.endAirport {
                self.route.isHidden = false
                self.route.attributedText = NSAttributedString(string: self.displayContext.format(airport: endAirport, style: .nameOnly), attributes: cellAttribute)
            }else{
                self.route.isHidden = true
            }
            
            if let distance = flightSummary.numberWithUnit(for: .Distance)?.formatDouble() {
                self.distance.attributedText = NSAttributedString(string: distance, attributes: cellAttribute)
            }else{
                self.distance.attributedText = NSAttributedString(string: "", attributes: cellAttribute)
            }
            
            var airports : [String] = []
            if let from = flightSummary.startAirport {
                airports.append(from.icao)
            }
            if let to = flightSummary.endAirport {
                airports.append(to.icao)
            }
            self.airports.attributedText = NSAttributedString(string: airports.joined(separator: "-"), attributes: titleAttribute)
        }else{
            self.date.attributedText = NSAttributedString(string: "Empty", attributes: cellAttribute)
            self.totalTime.attributedText = NSAttributedString(string: "", attributes: cellAttribute)
            self.flightTime.attributedText = NSAttributedString(string: "", attributes: cellAttribute)
            self.fuel.attributedText = nil
            self.route.attributedText = nil
            self.distance.attributedText = nil
            self.airports.attributedText = nil

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
