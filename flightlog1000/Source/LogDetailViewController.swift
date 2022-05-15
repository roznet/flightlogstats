//
//  LogDetailViewController.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 18/04/2022.
//

import UIKit
import OSLog

class LogDetailViewController: UIViewController,LogSelectionDelegate {
    var logFileOrganizer = FlightLogOrganizer.shared
    
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var name: UILabel!
    @IBOutlet weak var totalFuel: UILabel!
    @IBOutlet weak var fuelCollectionView: UICollectionView!
    
    @IBOutlet weak var legsCollectionView: UICollectionView!
    
    var flightLogFileInfo : FlightLogFileInfo? = nil
    var legsDataSource : FlightLegsDataSource? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(forName: .logFileInfoUpdated, object: nil, queue:nil){
            notification in
            DispatchQueue.main.async{
                self.updateUI()
            }
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
        if self.name != nil {
            self.name.text = self.flightLogFileInfo?.log_file_name
            self.totalFuel.text = self.flightLogFileInfo?.totalFuelDescription
            self.view.setNeedsDisplay()
        
            if let legs = self.flightLogFileInfo?.flightLog?.legs {
                let legsDataSource = FlightLegsDataSource(legs: legs)
                legsDataSource.prepare()
                self.legsDataSource = legsDataSource
                self.legsCollectionView.dataSource = self.legsDataSource
                self.legsCollectionView.delegate = self.legsDataSource
                if let tableCollectionLayout = self.legsCollectionView.collectionViewLayout as? TableCollectionViewLayout {
                    tableCollectionLayout.sizeDelegate = self.legsDataSource
                }else{
                    Logger.app.error("Internal error: Inconsistent layout ")
                }
                //self.fuelCollectionView.collectionViewLayout
            }else{
                self.legsDataSource = nil
                
            }
                
        }
    }
    
    func logInfoSelected(_ info: FlightLogFileInfo) {
        self.flightLogFileInfo = info
        
        DispatchQueue.main.async {
            self.progressView.setProgress(0.0, animated: false)
            self.progressView.isHidden = false
        }
        AppDelegate.worker.async {
            self.flightLogFileInfo?.parseAndUpdate() {
                val in
                DispatchQueue.main.async {
                    Logger.app.info( "progress \(val)")
                    self.progressView.setProgress( Float(val), animated: true )
                }
            }
            DispatchQueue.main.async {
                self.progressView.isHidden = true
                self.updateUI()
            }
        }
    }
}
