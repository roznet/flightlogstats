//
//  FlightLogTableViewCell.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 30/04/2022.
//

import UIKit

class FlightLogTableViewCell: UITableViewCell {
    
    var flightLogFileInfo : FlightLogFileInfo? = nil
    
    @IBOutlet weak var totalTime: UILabel!
    @IBOutlet weak var name: UILabel!
    @IBOutlet weak var fuel: UILabel!
    
    
    func update(with info: FlightLogFileInfo){
        self.flightLogFileInfo = info
        let flightSummary = info.flightSummary
        self.name.text = info.log_file_name
        self.totalTime.text = flightSummary?.hobbs.elapsedAsDecimalHours
        self.fuel.text = flightSummary?.fuelUsed.totalAsGallon
        
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
