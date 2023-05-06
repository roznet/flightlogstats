//
//  FlyStoLogUrlRequest.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 06/05/2023.
//

import Foundation
import UIKit
import RZUtilsSwift
import OSLog

class FlyStoLogFilesRequest : FlyStoRequest {
    private var fileId : String
    
    var url : URL? = nil
    
    init(viewController : UIViewController, fileId : String) {
        self.fileId = fileId
        super.init(viewController: viewController)
    }
    
    override func makeRequest(attempt : Int = 0){
        guard !self.oauth.client.credential.isTokenExpired() else {
            self.end(status: .error("Token should have been renewed but has expired"))
            return
        }
        
        let urlString = (Secrets.shared.value(for: "flysto.logFilesUrl") as NSString).appendingPathComponent(self.fileId)
        if let logfilesUrl = URL(string: urlString) {
            self.progress?.update(state: .progressing(0.5), message: .uploadingFiles)
            self.oauth.client.get(logfilesUrl) {
                result in
                switch result {
                case .success(let response):
                    if let interp = self.interpretResponse(data: response.data) {
                        Logger.net.info("got \(interp.logs)")
                        self.url = interp.urls.first
                    }else{
                        if let str = String(data: response.data, encoding: response.response.stringEncoding ?? .utf8) {
                            Logger.net.error("Couldn't interpret data \(str)")
                        }
                        self.url = nil
                    }
                    self.end(status: .success)
                case .failure(let queryError):
                    let status = self.processSwiftOAuthError(error: queryError)
                    switch status {
                    case .tokenExpired,.denied:
                        Self.clearCredential()
                        self.start(attempt: attempt + 1)
                    case .error:
                        self.end(status: .error("Failed \(queryError.localizedDescription)"))
                    case .success,.progressing(_):
                        self.end(status: .success)
                    case .already(let responseString):
                        Logger.net.info("Already? got \(responseString)")
                        self.end(status: .success)
                    }
                }
            }
        }else{
            self.end(status: .error("Failed to build file for upload"))
        }
    }
    
    struct LogFilesResponse : Codable {
        var logs : [String]
        var processed : Bool
        
        var urls : [URL] {
            return self.logs.compactMap { return URL(string: "https://www.flysto.net/logs/\($0)" ) }
        }
    }
    
    func interpretResponse(data : Data) -> LogFilesResponse? {
        if let res = try? JSONDecoder().decode(LogFilesResponse.self, from: data) {
            return res
        }
        return nil
    }
}
