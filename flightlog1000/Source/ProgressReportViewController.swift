//
//  ProgressReportViewController.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 05/06/2022.
//

import UIKit

class ProgressReportViewController: UIViewController {

    @IBOutlet weak var progressBar: UIProgressView!
    @IBOutlet weak var statusLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    

    func update(for report: ProgressReport) -> Bool {
        var rv = false
        let animate = self.statusLabel.text == report.message
        self.statusLabel.text = report.message
        switch report.state {
        case .progressing(let pct):
            self.progressBar.setProgress(Float(pct), animated: (animate && pct != 0.0))
        case .complete:
            self.progressBar.setProgress(1.0, animated: true)
            rv = true
        case .error(let error):
            self.statusLabel.text = error
            rv = true
        }
        return rv
    }
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

    
}
