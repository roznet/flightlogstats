//
//  ProgressReportViewController.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 05/06/2022.
//

import UIKit

class ProgressReportViewController: UIViewController {

    typealias Message = ProgressReport.Message
    
    @IBOutlet weak var progressBar: UIProgressView!
    @IBOutlet weak var statusLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    
    private var lastMessage : Message? = nil
    
    /// Animate if message is same, just update else set at once
    func shouldAnimate(for message : Message) -> Bool {
        var rv = false
        if let lastMessage = self.lastMessage {
            rv = (message == lastMessage)
        }
        self.lastMessage = message
        return rv
    }
    
    func reset(with message : Message) {
        self.lastMessage = message
        self.statusLabel.attributedText = NSAttributedString(string: message.description, attributes: ViewConfig.shared.progressAttributes)
        self.progressBar.setProgress(0, animated: false)
    }
    
    func update(for report: ProgressReport) -> Bool {
        var rv = false
        let animate = self.shouldAnimate(for: report.message)
        self.statusLabel.attributedText = NSAttributedString(string: report.message.description, attributes: ViewConfig.shared.progressAttributes)
        switch report.state {
        case .start:
            self.progressBar.setProgress(0.0, animated: false)
        case .progressing(let pct):
            self.progressBar.setProgress(Float(pct), animated: animate && pct != 0.0)
        case .complete:
            self.progressBar.setProgress(1.0, animated: !report.fastProcessing)
            rv = true
        case .error(let error):
            self.statusLabel.text = error
            rv = true
        }
        return rv
    }
}
