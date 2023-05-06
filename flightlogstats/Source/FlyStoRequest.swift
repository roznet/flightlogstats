//
//  FlyStoRequests.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 01/10/2022.
//
// GET https://www.flysto.net/public-api/log-files/<file-id>
// to obtain current information about the file:
// {
//    "processed": "true",
//    "logs": ["<log-id"]
// }

import Foundation
import OAuthSwift
import RZFlight
import UIKit
import OSLog
import ZIPFoundation
import RZUtilsSwift

extension FlightLogFileRecord {
    
    var flystoStatus : FlightFlyStoRecord.Status {
        get {
            return self.flysto_record?.status ?? .ready
        }
        set {
            self.ensureFlyStoStatus()
            self.flysto_record?.status = newValue
            self.flysto_record?.status_date = Date()
        }
    }
    var flystoUpdateDate : Date? {
        return self.flysto_record?.status_date
    }
    
    func flyStoUploadRequest(viewController : UIViewController) -> FlyStoUploadRequest? {
        if let url = self.url {
            let req = FlyStoUploadRequest(viewController: viewController, url: url)
            return req
        }
        return nil
    }
    
    func flyStoUploadCompletion(status : FlyStoRequest.Status, request : RemoteServiceRequest) {
        var checkflyStoStatus : FlightFlyStoRecord.Status = .ready
        switch status {
        case .progressing:
            return
        case .success,.already:
            checkflyStoStatus = .uploaded
        case .error,.tokenExpired,.denied:
            checkflyStoStatus = .failed
        }
        
        dispatchPrecondition(condition: .onQueue(AppDelegate.worker))
        
        self.flystoStatus = checkflyStoStatus
        if let uploadRequest = request as? FlyStoUploadRequest {
            if let resp = uploadRequest.uploadResponse,
               uploadRequest.interpretResponse(response: resp) != nil {
                Logger.net.info("Got valid upload Response \(resp)")
                self.flysto_record?.upload_response = resp
            }
        }

    }
}

class FlyStoRequest : RemoteServiceRequest{
    
    typealias Status = RemoteServiceRequest.Status
    typealias CompletionHandler = RemoteServiceRequest.CompletionHandler
    
    let oauth : OAuth2Swift
    let viewController : UIViewController
    
    var completionHandler : CompletionHandler? = nil

    init(viewController : UIViewController) {
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
            cb(status,self)
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
        return self.end(status: .success)
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
                let userInfo = (underlyingError as NSError).userInfo
                if
                   let responseString = userInfo["Response-Body"] as? String{
                    return .already(responseString)
                }else{
                    return .success
                }
                
            }else if code == 400 {
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
    
}
