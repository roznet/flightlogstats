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
        self.name.text = info.flightLog?.name
        self.fuel.text = info.totalFuelDescription
        
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
