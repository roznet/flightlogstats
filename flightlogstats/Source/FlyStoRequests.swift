//
//  FlyStoRequests.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 01/10/2022.
//

import Foundation
import OAuthSwift
import RZFlight
import UIKit
import OSLog
import ZIPFoundation

class FlyStoRequests {
    
    typealias CompletionHandler = (Status) -> Void
    
    enum Status {
        case success
        case already
        case error
    }
    
    let oauth : OAuth2Swift
    let viewController : UIViewController
    
    let url : URL
    var uploadFileUrl : URL { return self.url.appendingPathExtension("zip") }
    var completionHandler : CompletionHandler? = nil

    init(viewController : UIViewController, url : URL) {
        self.url = url
        self.viewController = viewController
        self.oauth = OAuth2Swift(consumerKey: Secrets.shared.value(for: "flysto.consumerKey"),
                            consumerSecret: Secrets.shared.value(for: "flysto.consumerSecret"),
                            authorizeUrl: Secrets.shared.value(for: "flysto.authorizeUrl"),
                                 accessTokenUrl: Secrets.shared.value(for: "flysto.accessTokenUrl"),
                            responseType: "code")
        self.oauth.allowMissingStateCheck = true
        self.oauth.authorizeURLHandler = SafariURLHandler(viewController: self.viewController, oauthSwift: self.oauth)
        
    }
    
    @discardableResult func retrieveCredential() -> Bool {
        if let credentials = Settings.shared.flystoCredentials {
            self.oauth.client.credential.oauthToken = credentials.oauthToken
            self.oauth.client.credential.oauthTokenSecret = credentials.oauthTokenSecret
            self.oauth.client.credential.oauthRefreshToken = credentials.oauthRefreshToken
            return true
        }
        return false
    }
    
    func saveCredential() {
        Settings.shared.flystoCredentials = self.oauth.client.credential
    }
    
    func clearCredential() {
        Settings.shared.flystoCredentials = nil
    }
    
    func start(completion : @escaping CompletionHandler) {
        self.completionHandler = completion
        Logger.net.info("start upload \(self.url.lastPathComponent)")
        if !self.retrieveCredential() {
            let callback = URL(string: Secrets.shared.value(for: "flysto.callbackUrl"))
            
            self.oauth.authorize(withCallbackURL: callback, scope: "", state: ""){
                result in
                Logger.net.info("Callback from oauth")
                switch result {
                case .success:
                    Logger.net.info("authorized")
                    self.saveCredential()
                    self.makeRequest()
                case .failure(let error):
                    Logger.net.error("Failed \(error.localizedDescription)")
                    self.end(status: .error)
                }
            }
        }else{
            self.makeRequest()
        }
    }
    
    func end(status : Status){
        if let cb = self.completionHandler {
            cb(status)
        }
        
        self.completionHandler = nil
    }
    
    func makeRequest(tokenRefreshed : Bool = false){
        guard !self.oauth.client.credential.isTokenExpired() else {
            self.refreshTokenAndTryAgain()
            return
        }
        
        if let data = self.buildUploadFile(),
           let upload = URL(string: Secrets.shared.value(for: "flysto.uploadLogUrl")) {
            self.oauth.client.post(upload, body: data) {
                result in
                switch result {
                case .success(let response):
                    Logger.net.info("upload of \(self.url.lastPathComponent) successfull \(response.description)")
                    self.end(status: .success)
                case .failure(let queryError):
                    switch queryError {
                    case .requestError(let underlyingError, _ /*request:*/ ):
                        let code = (underlyingError as NSError).code
                        
                        if code == 503 { // applicaiton error
                            // application error, login again
                            Logger.net.info("Application error, clearing credentials: \(code)")
                            self.refreshTokenAndTryAgain()
                        }else if code == 409 {
                            Logger.net.info("File \(self.url.lastPathComponent) was already uploaded (code \(code))")
                            self.end(status: .success)
                        }else{
                            Logger.net.info("Underlying request error: \(code)")
                            self.end(status: .error)
                        }
                    case .accessDenied(let underlyingError, _ /*request:*/):
                        let code = (underlyingError as NSError).code
                        Logger.net.info("Access Denied: \(code)")
                        // force login
                        Settings.shared.flystoCredentials = nil
                        self.end(status: .error)
                    case .tokenExpired:
                        if !tokenRefreshed {
                            self.refreshTokenAndTryAgain()
                        }else{
                            self.clearCredential()
                            self.end(status: .error)
                        }
                    default:
                        Logger.net.error("Other error \(queryError.localizedDescription)")
                        self.end(status: .error)
                    }
                }
            }
        }else{
            self.end(status: .error)
        }
    }
    
    func refreshTokenAndTryAgain() {
        Logger.net.info("Refreshing expired token")
        self.oauth.renewAccessToken(withRefreshToken: self.oauth.client.credential.oauthRefreshToken){
            result in
            switch result{
            case .success:
                Logger.net.info("Successfully Refreshed token")
                self.saveCredential()
                self.makeRequest(tokenRefreshed: true)
            case .failure(let error):
                Logger.net.error("Failed to refresh token \(error.localizedDescription)")
                self.end(status: .error)
            }
        }

    }
    
    func clearUploadFile() {
        if FileManager.default.fileExists(atPath: self.uploadFileUrl.path) {
            do {
                try FileManager.default.removeItem(at: self.uploadFileUrl)
            }catch{
                Logger.net.error("Failed to remove archive \(error.localizedDescription)")
            }
        }
    }
    
    func buildUploadFile() -> Data? {
        self.clearUploadFile()
        if let archive = Archive(url: self.uploadFileUrl, accessMode: .create){
            do {
                try archive.addEntry(with: self.url.lastPathComponent, fileURL: self.url)
                return try Data(contentsOf: self.uploadFileUrl)
            }catch{
                Logger.net.error("Failed to create zip file \(error.localizedDescription)")
            }
        }
        return nil
    }
    
}
