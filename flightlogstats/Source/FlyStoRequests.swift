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
    
    typealias Status = RemoteServiceRequest.Status
    typealias CompletionHandler = RemoteServiceRequest.CompletionHandler
    
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
        #if targetEnvironment(macCatalyst)
        self.oauth.authorizeURLHandler = OAuthSwiftOpenURLExternally.sharedInstance
        #else
        self.oauth.authorizeURLHandler = SafariURLHandler(viewController: self.viewController, oauthSwift: self.oauth)
        #endif
        
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
    
    static var hasCredential : Bool {
        return Settings.shared.flystoCredentials != nil
    }
    
    func saveCredential() {
        Settings.shared.flystoCredentials = self.oauth.client.credential
    }
    
    static func clearCredential() {
        Settings.shared.flystoCredentials = nil
    }
    
    func execute(completion : @escaping CompletionHandler) {
        self.completionHandler = completion
        self.start(attempt: 0)
    }
    
    func start(attempt : Int = 0){
        guard attempt < 2 else {
            self.end(status: .error("More than 2 attemps failed, aborting"))
            return
        }
        Logger.net.info("start upload[\(attempt)] \(self.url.lastPathComponent)")
        if !self.retrieveCredential() {
            let callback = URL(string: Secrets.shared.value(for: "flysto.callbackUrl"))
            Logger.net.info("starting full authorize process")
            self.oauth.authorize(withCallbackURL: callback, scope: "", state: ""){
                result in
                Logger.net.info("Callback from oauth")
                switch result {
                case .success:
                    Logger.net.info("authorized")
                    self.saveCredential()
                    self.makeRequest(attempt: attempt)
                case .failure(let error):
                    self.end(status: .error("Failed \(error.localizedDescription)"))
                }
            }
        }else{
            self.refreshToken(attempt: attempt)
        }
    }
    
    func end(status : Status){
        if case .error(let message) = status {
            Logger.net.error(message)
        }
        if let cb = self.completionHandler {
            cb(status)
        }
        
        self.completionHandler = nil
    }
    
    func refreshToken(attempt : Int = 0) {
        Logger.net.info("Refreshing token")
        self.oauth.renewAccessToken(withRefreshToken: self.oauth.client.credential.oauthRefreshToken){
            result in
            switch result{
            case .success:
                Logger.net.info("Successfully Refreshed token")
                self.saveCredential()
                self.makeRequest(attempt: attempt)
            case .failure(let error):
                let status = self.processSwiftOAuthError(error: error)
                if status == .denied {
                    Logger.net.info("Failed to refresh token, attempting full authorize")
                    Self.clearCredential()
                    self.start(attempt: attempt + 1)
                }else{
                    self.end(status: .error("Failed \(error.localizedDescription)"))
                }
            }
        }
    }

    func makeRequest(attempt : Int = 0){
        guard !self.oauth.client.credential.isTokenExpired() else {
            self.end(status: .error("Token should have been renewed but has expired"))
            return
        }
        
        if let data = self.buildUploadFile(),
           let upload = URL(string: Secrets.shared.value(for: "flysto.uploadLogUrl")) {
            if let cb = self.completionHandler {
                cb(FlyStoRequests.Status.progressing(0.5))
            }
            self.oauth.client.post(upload, body: data) {
                result in
                switch result {
                case .success(let response):
                    Logger.net.info("upload of \(self.url.lastPathComponent) successfull \(response.description)")
                    self.end(status: .success)
                case .failure(let queryError):
                    let status = self.processSwiftOAuthError(error: queryError)
                    switch status {
                    case .tokenExpired,.denied:
                        Self.clearCredential()
                        self.start(attempt: attempt + 1)
                    case .error:
                        self.end(status: .error("Failed \(queryError.localizedDescription)"))
                    case .success,.progressing(_),.already:
                        self.end(status: .success)
                    }
                }
            }
        }else{
            self.end(status: .error("Failed to build file for upload"))
        }
    }
    
    @discardableResult func processSwiftOAuthError(error : OAuthSwiftError) -> Status {
        switch error {
        case .requestError(let underlyingError, _ /*request:*/ ):
            let code = (underlyingError as NSError).code
            
            if code == 503 { // application error
                // application error, login again
                Logger.net.info("Token has expired, status: \(code)")
                return .tokenExpired
            }else if code == 409 {
                Logger.net.info("File \(self.url.lastPathComponent) was already uploaded (code \(code))")
                return .success
            }else if code == 400 {
                Logger.net.info("File \(self.url.lastPathComponent) application error (code \(code))")
                return .denied
            }else{
                Logger.net.info("Underlying request error: \(code)")
                return .error("Underlying request error: \(code)")
            }
        case .accessDenied(let underlyingError, _ /*request:*/):
            let code = (underlyingError as NSError).code
            Logger.net.info("Access Denied: \(code)")
            // force login
            Settings.shared.flystoCredentials = nil
            return .denied
        case .tokenExpired:
            Logger.net.error("Token has expired")
            return .tokenExpired
        default:
            Logger.net.error("Other error \(error.localizedDescription)")
            return .error("Other error \(error.localizedDescription)")
        }
    }
    
    //MARK: - Upload file
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
