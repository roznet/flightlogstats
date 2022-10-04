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

class FlyStoRequests {
    let oauth : OAuth2Swift
    let navigationController : UINavigationController

    init(navigationController : UINavigationController) {
        self.navigationController = navigationController
        self.oauth = OAuth2Swift(consumerKey: Secrets.shared.value(for: "flysto.consumerKey"),
                            consumerSecret: Secrets.shared.value(for: "flysto.consumerSecret"),
                            authorizeUrl: Secrets.shared.value(for: "flysto.authorizeUrl"),
                                 accessTokenUrl: Secrets.shared.value(for: "flysto.accessTokenUrl"),
                            responseType: "code")
        self.oauth.authorizeURLHandler = SafariURLHandler(viewController: self.navigationController, oauthSwift: self.oauth)
        
    }
    
    func retrieveCredential() -> Bool {
        let credentialsData = Settings.shared.flystoCredentials
        if let credentials = try? JSONDecoder().decode(OAuthSwiftCredential.self, from: credentialsData) {
            self.oauth.client.credential.oauthToken = credentials.oauthToken
            self.oauth.client.credential.oauthTokenSecret = credentials.oauthTokenSecret
            self.oauth.client.credential.oauthRefreshToken = credentials.oauthRefreshToken
            return true
        }
        return false
    }
    
}
