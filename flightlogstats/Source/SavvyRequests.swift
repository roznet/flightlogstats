//
//  SavvyRequests.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 28/01/2023.
//

import Foundation
import UIKit
import WebKit
import OSLog
import RZUtilsSwift

// UIViewController with a WKWebView and a callback to handle the result
// Documentation in https://github.com/savvyaviation/api-docs
class SavvyAuthenticateViewController : UIViewController, WKNavigationDelegate {
    
    enum Status {
        case token(String)
        case failed(Error)
        case canceled
    }
    typealias CompletionHandler = (Status) -> Void
    @IBOutlet var webView : WKWebView? = nil
    var callback : CompletionHandler? = nil
    var url : URL? = URL(string: "https://apps.savvyaviation.com/request-api-token/?app_name=FlightLogStats&callback_url=flightlogstats://ro-z.net/savvy/token")
    
    @IBAction func doneButton(_ sender: Any) {
        self.callback?(.canceled)
        self.dismiss(animated: true)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.webView?.navigationDelegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        //self.url = URL(string: "https://www.google.com")
        if let url = self.url {
            Logger.web.info("Starting \(url)")
            self.webView?.load(URLRequest(url: url))
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, url.scheme == "flightlogstats" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let queryItems = components.queryItems {
                for item in queryItems {
                    if item.name == "token" {
                        if let token = item.value {
                            Logger.ui.info("Savvy: Got token \(token)")
                            self.callback?(.token(token))
                            self.callback = nil
                        }
                    }
                }
            }
            // callback is called only once, because if called before, will be nil
            self.callback?(.failed(NSError(domain: "Savvy", code: 1, userInfo: [NSLocalizedDescriptionKey:"No token returned"])))
            decisionHandler(.cancel)
            self.dismiss(animated: true)
            return
        }
        decisionHandler(.allow)
    }
}

class SavvyRequests {
    typealias CompletionHandler = (Status) -> Void
    typealias AircraftIdentifier = AircraftRecord.AircraftIdentifier
    
    struct SavvyAircraft : Codable {
        let registration_no : String
        let id : Int
    }
    //SavvyAircraft Upload Response
    //sample: {"status": "OK", "id": 550, "logs": "/file_parse_log/550”}
    struct SavvyUploadResponse : Codable {
        let status : String
        let logs: String
        let id : Int
    }
    enum Status {
        case success
        case error(String)
        case progressing(Double)
        case inconsistentAircraft
        case denied
    }
    let viewController : UIViewController
    let url : URL
    let aircraftIdentifier : AircraftIdentifier

    init(viewController : UIViewController, url : URL, aircraftIdentifier : AircraftIdentifier) {
        self.viewController = viewController
        self.url = url
        self.aircraftIdentifier = aircraftIdentifier
    }

    func execute(completion : @escaping CompletionHandler){
        self.start()
    }
    static var hasCredential : Bool {
        return Settings.shared.savvyToken != nil
    }
    static func clearCredential() {
        Settings.shared.savvyToken = nil
    }

    func start(attempt : Int = 0) {
        
        guard attempt < 2 else {
            Logger.net.error("Savvy: Too many attempts")
            self.end(status: .error("Too many attempts"))
            return
        }
        
        if let token = Settings.shared.savvyToken {
            self.startRequest(token: token)
        }else{
            self.authenticate(viewController: self.viewController) { status in
                switch status {
                case .token(let token):
                    Settings.shared.savvyToken = token
                    self.startRequest(token: token)
                case .failed(let error):
                    Logger.net.error("Savvy: Failed to get token \(error)")
                    self.end(status: .error("Failed to get token"))
                case .canceled:
                    Logger.net.error("Savvy: Canceled")
                    self.end(status: .denied)
                }
            }
        }
    }
    func authenticate(viewController : UIViewController, callback : @escaping SavvyAuthenticateViewController.CompletionHandler) {
        let storyboard : UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
        let vc = storyboard.instantiateViewController(identifier: "serviceLoginViewController")
        vc.modalPresentationStyle = .fullScreen
        if let savvy = vc as? SavvyAuthenticateViewController {
            savvy.callback = callback
            viewController.present(savvy, animated: true)
        }
    }
    func startRequest(token : String) {
        self.startAircraftRequest()
    }
    func startAircraftRequest() {
        if let token = Settings.shared.savvyToken,
           let aircraftUrl = URL(string: "https://apps.savvyaviation.com/get-aircraft/") {
           //let aircraftUrl = URL(string: "https://localhost.ro-z.me/savvy/get-aircraft.php") {
            let  builder = MultipartRequestBuilder(url: aircraftUrl)
            builder.addField(name: "token", value: token)
            let request = builder.request()
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    Logger.net.error("Savvy: Failed to get aircraft \(error)")
                    self.end(status: .error("Failed to get aircraft"))
                }else if let data = data {
                    do {
                        let decoder = JSONDecoder()
                        let aircrafts = try decoder.decode([SavvyAircraft].self, from: data)
                        Logger.net.info("Savvy: Got \(aircrafts.count) aircraft")
                        self.startUploadForMatchinAircraft(aircrafts: aircrafts)
                    }catch let error {
                        if let txt = String(data: data, encoding: .utf8) {
                            Logger.net.info("Response: \(txt)")
                        }
                        Logger.net.error("Savvy: Failed to decode aircraft \(error)")
                        self.end(status: .error("Failed to decode aircraft"))
                    }
                }
            }
            task.resume()
        }
    }
    func startUploadForMatchinAircraft(aircrafts : [SavvyAircraft]){
        for aircraft in aircrafts {
            if self.aircraftIdentifier.lowercased() == aircraft.registration_no.lowercased() {
                Logger.net.info("Found matching aircraft \(self.aircraftIdentifier) id=\(aircraft.id)")
                self.startUploadRequest(aircraftId: aircraft.id)
                return
            }
        }
        Logger.net.error("Savvy: No matching aircraft")
        self.end(status: .error("No Matching aircraft"))
    }
    func startUploadRequest(aircraftId : Int) {
        let urls = "https://apps.savvyaviation.com/upload_files_api/\(aircraftId)"
        if let token = Settings.shared.savvyToken,
           let uploadUrl = URL(string: urls) {
            let  builder = MultipartRequestBuilder(url: uploadUrl)
            builder.addField(name: "token", value: token)
            let filename = self.url.lastPathComponent
            builder.addFile(name: "file", filename: filename, url: self.url, mimeType: "text/csv")
            let request = builder.request()
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    Logger.net.error("Savvy: Failed to upload \(error)")
                    self.end(status: .error("Failed to upload"))
                }else if let data = data {
                    do {
                        let decoder = JSONDecoder()
                        let result = try decoder.decode(SavvyUploadResponse.self, from: data)
                        if result.status == "OK" {
                            Logger.net.info("Savvy: Uploaded \(filename)")
                            self.end(status: .success)
                        }else{
                            Logger.net.error("Savvy: Failed to upload \(filename) status \(result.status)")
                            self.end(status: .error("Failed to upload \(filename) status \(result.status)"))
                        }
                    }catch let error {
                        if let txt = String(data: data, encoding: .utf8) {
                            Logger.net.info("Response: \(txt)")
                        }
                        Logger.net.error("Savvy: Failed to decode aircraft \(error)")
                        self.end(status: .error("Failed to decode aircraft"))
                    }
                }
            }
            task.resume()
        }
    }
                
    func end(status : Status) {
    }
}

