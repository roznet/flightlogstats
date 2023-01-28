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

// UIViewController with a WKWebView and a callback to handle the result
// Documentation in https://github.com/savvyaviation/api-docs
class SavvyRequests : UIViewController, WKNavigationDelegate {
    var webView : WKWebView? = nil
    var callback : ((String)->Void)? = nil
    var url : URL? = URL(string: "https://apps.savvyaviation.com/request-api-token/?app_name=FlightLogStats&callback_url=flightlogstats://ro-z,net/savvy/token")

    override func loadView() {
        let webConfiguration = WKWebViewConfiguration()
        self.webView = WKWebView(frame: .zero, configuration: webConfiguration)
        self.webView?.navigationDelegate = self
        self.view = self.webView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if let url = self.url {
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
                            self.callback?(token)
                        }
                    }
                }
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
