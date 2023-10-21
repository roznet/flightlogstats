//
//  BugReportViewController.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 14/10/2023.
//

import UIKit
import WebKit
import OSLog
import DeviceGuru
import RZUtils
import ZIPFoundation
import RZUtilsSwift

class BugReportViewController: UIViewController,WKNavigationDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    var url : URL? = URL(string: Secrets.shared["flightlogstats.bugreport"] ?? "")
    var bugFilePath : String = RZFileOrganizer.writeableFilePath("bugreport.zip")
    
    @IBOutlet weak var webView: WKWebView!
    
    @IBOutlet weak var activityIndicatorView: UIActivityIndicatorView!
    
    @IBAction func doneButton(_ sender: Any) {
        self.dismiss(animated: true)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.activityIndicatorView.startAnimating()
        self.webView.navigationDelegate = self
        AppDelegate.worker.async {
            if let urlreq = self.urlRequest() {
                Logger.web.info("Starting bug report")
                DispatchQueue.main.async {
                    self.webView?.load(urlreq)
                }
            }

        }
    }
    
    func urlRequest() -> URLRequest? {
        if let url = self.url,
           self.createBugReportArchive() {
            let fileurl = URL(filePath: self.bugFilePath)
            let multi = MultipartRequestBuilder(url: url)
            let dict = self.createBugReportDictionary(extra: [:])
            multi.addFields(fields: dict)
            multi.addFile(name: "file", filename: "bugreport.zip", url: fileurl, mimeType: "application/x-zip")
            return multi.request()
        }
                          
        return nil
    }
    
    func createBugReportDictionary(extra : [String:String] ) -> [String:String] {
        
        let applicationName = "FlightLogStats"
        let buildString = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let versionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let device = UIDevice()
        let deviceGuru = DeviceGuruImplementation()
        let commonid = Settings.shared.commonBugId
        let platform = try? deviceGuru.hardwareDescription()
        
        var rv : [String:String] = [
            "systemName" : device.systemName,
            "systemVersion": device.systemVersion,
            "applicationName" : applicationName,
            "version" : versionString ?? "Unknown Version",
            "build" : buildString ?? "Unknown Build",
            "platformString": platform ?? "Unknown Device",
            "commonid" : "\(commonid)"
        ]
        
        if let buildString = buildString,
            let versionString = versionString {
            if buildString.hasPrefix(versionString) {
                rv["version"] = buildString
            }else{
                rv["version"] = "\(versionString) (\(buildString))"
            }
        }

        extra.forEach { (k,v) in rv[k] = v }

        if( commonid != -1){
            Logger.web.info("Had previous bug report: id=\(commonid)")
        }
        
        return rv
    }
    
    func createBugReportArchive() -> Bool {
        let bugPath = self.bugFilePath
        let bugPathURL = URL(fileURLWithPath: bugPath )
        var archiveSucess = true
        
        let archive = Archive(url: bugPathURL, accessMode: .create)
        let lines = Logger.logEntriesFormatted(hours: 24)
        if let data = lines.joined(separator: "\n").data(using: .utf8){
            do {
                try archive?.addEntry(with: "bugreport.log", type: .file, uncompressedSize: Int64(data.count)){
                    (position : Int64,size:Int) throws -> Data in
                    let start = Int(position), end = start+size
                      return data.subdata(in: start..<end)
                }
            }catch{
                archiveSucess = false
            }
        }
       
        
        return archiveSucess
    
    }
    
    @objc func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.activityIndicatorView.stopAnimating()
        self.activityIndicatorView.hidesWhenStopped = true
        self.webView.evaluateJavaScript("document.getElementById('commonid').value"){
            rv, err in
            if let cid = rv as? String {
                Logger.ui.info("Found common id \(cid)")
                Settings.shared.commonBugId = (cid as NSString).integerValue
            }else if let cid = rv as? Int {
                Logger.ui.info("Found common id \(cid)")
                Settings.shared.commonBugId = cid
            }else{
                Logger.ui.warning("Could not find common id")
            }
            
        }
    }

}
