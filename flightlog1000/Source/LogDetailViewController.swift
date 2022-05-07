//
//  LogDetailViewController.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 18/04/2022.
//

import UIKit

class LogDetailViewController: UIViewController,LogSelectionDelegate {
    @IBOutlet weak var name: UILabel!
    @IBOutlet weak var totalFuel: UILabel!
    
    var flightLogFileInfo : FlightLogFileInfo? = nil {
        didSet {
            updateUI()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(forName: .logFileInfoUpdated, object: nil, queue:nil){
            notification in
            self.updateUI()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

    func updateUI(){
        self.name.text = self.flightLogFileInfo?.log_file_name
        self.totalFuel.text = self.flightLogFileInfo?.totalFuelDescription
        self.view.setNeedsDisplay()
    }
    
    func logInfoSelected(_ info: FlightLogFileInfo) {
        self.flightLogFileInfo = info
    }
}
