//
//  FlyStoUploadRequest.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 06/05/2023.
//

import Foundation
import UIKit
import OAuthSwift
import RZFlight
import UIKit
import OSLog
import ZIPFoundation
import RZUtilsSwift

class FlyStoUploadRequest : FlyStoRequest {
    let url : URL
    var uploadFileUrl : URL { return self.url.appendingPathExtension("zip") }
    
    var uploadResponse : String? = nil
    
    init(viewController : UIViewController, url : URL) {
        self.url = url
        super.init(viewController: viewController)
    }
    
    override func makeRequest(attempt : Int = 0){
        guard !self.oauth.client.credential.isTokenExpired() else {
            self.end(status: .error("Token should have been renewed but has expired"))
            return
        }
        self.progress?.update(state: .progressing(0.3), message: .uploadingFiles)
        if let data = self.buildUploadFile(),
           let upload = URL(string: Secrets.shared.value(for: "flysto.uploadLogUrl")) {
            self.progress?.update(state: .progressing(0.5), message: .uploadingFiles)
            self.oauth.client.post(upload, body: data) {
                result in
                switch result {
                case .success(let response):
                    if let string = String(data: response.data, encoding: response.response.stringEncoding ?? .utf8) {
                        self.extractFileId(from: string)
                    }
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
                    case .success,.progressing(_):
                        self.end(status: .success)
                    case .already(let responseString):
                        self.extractFileId(from: responseString)
                        self.end(status: .success)
                    }
                }
            }
        }else{
            self.end(status: .error("Failed to build file for upload"))
        }
    }
    
    struct UploadResponse : Codable {
        var fileId : String
    }
    
    static func interpretResponse(response : String?) -> UploadResponse? {
        if let data = response?.data(using: .utf8),
           let res = try? JSONDecoder().decode(UploadResponse.self, from: data) {
            return res
        }
        return nil
    }

    func extractFileId(from response : String) {
        if Self.interpretResponse(response: response) != nil {
            self.uploadResponse = response
        }else{
            self.uploadResponse = nil
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
                try archive.addEntry(with: self.url.lastPathComponent, fileURL: self.url, compressionMethod: .deflate)
                return try Data(contentsOf: self.uploadFileUrl)
            }catch{
                Logger.net.error("Failed to create zip file \(error.localizedDescription)")
            }
        }
        return nil
    }
}
