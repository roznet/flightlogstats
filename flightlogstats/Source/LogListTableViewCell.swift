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
    
    func shouldRefresh(for info : FlightLogFileInfo) -> Bool {
        if let current = self.flightLogFileInfo {
            return info.log_file_name == current.log_file_name
        }else{
            return false
        }
    }
    
    func refresh() {
        if let info = self.flightLogFileInfo {
            self.update(with: info)
        }
    }
    
    func update(minimum info: FlightLogFileInfo){
        self.flightLogFileInfo = info
        
        let titleAttribute = ViewConfig.shared.titleAttributes
        let cellAttribute = ViewConfig.shared.cellAttributes

        self.fileName.text = info.log_file_name
        if let guess = info.log_file_name?.logFileGuessedAirport {
            self.airports.attributedText = NSAttributedString(string: guess, attributes: titleAttribute)
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        if let start_time = info.start_time {
            self.date.attributedText = NSAttributedString(string: formatter.string(from: start_time), attributes: cellAttribute)
        }else{
            self.date.attributedText = NSAttributedString(string: "Missing", attributes: cellAttribute)
        }

        self.route.isHidden = true
        self.flightIcon.isHidden = true
        self.flightTime.isHidden = true

    }
    
    func update(with info: FlightLogFileInfo){
        self.update(minimum: info)
        
        let titleAttribute = ViewConfig.shared.titleAttributes
        let cellAttribute = ViewConfig.shared.cellAttributes
        
        if let flightSummary = info.flightSummary {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
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
            
            if let total = flightSummary.measurement(for: .FuelTotalizer),
               let used = flightSummary.measurement(for: .FuelUsed) {
                let str = self.displayContext.formatValue(gallon: total.value != 0.0 ? total : used)
                self.fuel.attributedText = NSAttributedString(string: str, attributes: cellAttribute)
            }else{
                self.fuel.attributedText = NSAttributedString(string: "", attributes: cellAttribute)
            }
            
            if let endAirport = flightSummary.endAirport {
                self.route.isHidden = false
                self.route.attributedText = NSAttributedString(string: self.displayContext.format(airport: endAirport, style: .nameOnly), attributes: cellAttribute)
            }else{
                self.route.isHidden = true
            }
            
            if let distance = flightSummary.measurement(for: .Distance) {
                let str = self.displayContext.formatValue(distance: distance)
                self.distance.attributedText = NSAttributedString(string: str, attributes: cellAttribute)
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
        let cellAttribute = ViewConfig.shared.cellAttributes
        self.date.attributedText = NSAttributedString(string: "", attributes: cellAttribute)
        self.totalTime.attributedText = NSAttributedString(string: "", attributes: cellAttribute)
        self.flightTime.attributedText = NSAttributedString(string: "", attributes: cellAttribute)
        self.fuel.attributedText = NSAttributedString(string: "", attributes: cellAttribute)
        self.route.attributedText = NSAttributedString(string: "", attributes: cellAttribute)
        self.distance.attributedText = NSAttributedString(string: "", attributes: cellAttribute)
        self.airports.attributedText = NSAttributedString(string: "Pending", attributes: cellAttribute)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
