//
//  FlyStoService.swift
//  FlightLogStats
//
//  FlySto: OAuth2 sign in, token refresh, zipped log upload, log page lookup.
//
// GET https://www.flysto.net/public-api/log-files/<file-id>
// to obtain current information about the file:
// {
//    "processed": "true",
//    "logs": ["<log-id"]
// }

import Foundation
import AuthenticationServices
import OAuthSwift
import OSLog
import UIKit
import ZIPFoundation
import RZUtilsSwift

actor FlyStoService : UploadService {
    static let shared = FlyStoService()

    private let keychain : KeychainStore
    private let isEnabled : @Sendable () -> Bool
    private var credential : OAuthSwiftCredential? = nil
    /// set when FlySto rejected the credential: only a sign in clears it
    private var rejected : Bool = false
    /// one refresh at a time: concurrent callers wait for the same one (U2)
    private var refreshTask : Task<Void,Error>? = nil

    static let credentialAccount = "credential"

    init(keychain : KeychainStore = KeychainStore(service: "net.ro-z.flightlogstats.flysto"),
         isEnabled : @escaping @Sendable () -> Bool = { Settings.shared.flystoEnabled }) {
        self.keychain = keychain
        self.isEnabled = isEnabled
        self.credential = Self.loadCredential(keychain: keychain)
    }

    //MARK: - Credential

    /// From the Keychain, moving it there from UserDefaults the first time (U4).
    private static func loadCredential(keychain : KeychainStore) -> OAuthSwiftCredential? {
        if let data = keychain.data(for: Self.credentialAccount),
           let credential = try? JSONDecoder().decode(OAuthSwiftCredential.self, from: data) {
            return credential
        }
        if let legacy = Settings.shared.flystoCredentials {
            if let data = try? JSONEncoder().encode(legacy), keychain.set(data, for: Self.credentialAccount) {
                Settings.shared.flystoCredentials = nil
                Logger.net.info("Moved FlySto credential to the Keychain")
            }
            return legacy
        }
        return nil
    }

    private func save(_ credential : OAuthSwiftCredential?) {
        self.credential = credential
        if let credential = credential, let data = try? JSONEncoder().encode(credential) {
            self.keychain.set(data, for: Self.credentialAccount)
        }else{
            self.keychain.set(nil, for: Self.credentialAccount)
        }
    }

    var hasCredential : Bool { return self.credential != nil }

    /// Sign out: forget the credential.
    func signOut() {
        self.save(nil)
        self.rejected = false
    }

    /// Keep the credential from a sign in.
    func signedIn(_ credential : OAuthSwiftCredential) {
        self.save(credential)
        self.rejected = false
    }

    //MARK: - UploadService

    func state() -> ServiceState {
        guard self.isEnabled() else { return .disabled }
        if self.credential == nil || self.rejected {
            return .needsSignIn
        }
        return .ready
    }

    func upload(file : URL) async throws -> UploadReceipt {
        guard self.credential != nil, !self.rejected else {
            throw UploadFailure.auth("Sign in to FlySto")
        }
        guard let uploadUrl = URL(string: Secrets.shared.value(for: "flysto.uploadLogUrl")) else {
            throw UploadFailure.permanent("No FlySto upload URL configured")
        }
        let body = try Self.zip(file)
        let response = try await self.authorized { client in
            try await Self.post(client: client, url: uploadUrl, body: body)
        }
        let string = String(data: response.data, encoding: response.response.stringEncoding ?? .utf8)
        return UploadReceipt(response: Self.fileIdResponse(string))
    }

    /// The FlySto page of an uploaded log, from the upload's `{"fileId"}` answer.
    func logPage(for receipt : UploadReceipt) async throws -> URL? {
        guard let fileId = Self.fileId(from: receipt.response) else { return nil }
        let urlString = (Secrets.shared.value(for: "flysto.logFilesUrl") as NSString).appendingPathComponent(fileId)
        guard let url = URL(string: urlString) else { return nil }
        let response = try await self.authorized { client in
            try await Self.get(client: client, url: url)
        }
        struct LogFilesResponse : Codable {
            var logs : [String]
        }
        guard let files = try? JSONDecoder().decode(LogFilesResponse.self, from: response.data),
              let log = files.logs.first else { return nil }
        return URL(string: "https://www.flysto.net/logs/\(log)")
    }

    //MARK: - Requests

    /// Run a request with a valid token: refresh first only if expired, and once more after
    /// a 401 (or FlySto's 503 for an expired token). Never opens a sign in page.
    private func authorized(_ request : (OAuthSwiftClient) async throws -> OAuthSwiftResponse) async throws -> OAuthSwiftResponse {
        guard let credential = self.credential, !self.rejected else {
            throw UploadFailure.auth("Sign in to FlySto")
        }
        if credential.isTokenExpired() {
            try await self.refresh()
        }
        do {
            return try await request(self.client())
        }catch let error as OAuthSwiftError {
            switch Self.classify(error) {
            case .refreshAndRetry(let status):
                Logger.net.info("FlySto answered \(status), refreshing the token and trying again")
                try await self.refresh()
                do {
                    return try await request(self.client())
                }catch let error as OAuthSwiftError {
                    let failure = Self.classify(error).failure(retried: true)
                    if case .auth = failure {
                        self.rejected = true
                    }
                    throw failure
                }
            case let outcome:
                throw outcome.failure(retried: false)
            }
        }
    }

    private func refresh() async throws {
        if let running = self.refreshTask {
            return try await running.value
        }
        let task = Task { try await self.performRefresh() }
        self.refreshTask = task
        defer { self.refreshTask = nil }
        try await task.value
    }

    private func performRefresh() async throws {
        guard let refreshToken = self.credential?.oauthRefreshToken, !refreshToken.isEmpty else {
            self.rejected = true
            throw UploadFailure.auth("Sign in to FlySto")
        }
        Logger.net.info("Refreshing FlySto token")
        let oauth = Self.makeOAuth(credential: self.credential)
        do {
            let _ : OAuthSwift.TokenSuccess = try await withCheckedThrowingContinuation { continuation in
                oauth.renewAccessToken(withRefreshToken: refreshToken) { result in
                    continuation.resume(with: result)
                }
            }
            self.save(oauth.client.credential)
        }catch{
            let outcome = Self.classify(error)
            if case .transient(let message) = outcome.failure(retried: true) {
                throw UploadFailure.transient(message)
            }
            // the refresh token itself is refused
            Logger.net.error("FlySto refresh refused \(error.localizedDescription)")
            self.rejected = true
            throw UploadFailure.auth("FlySto sign in expired")
        }
    }

    private func client() -> OAuthSwiftClient {
        return Self.makeOAuth(credential: self.credential).client
    }

    static func makeOAuth(credential : OAuthSwiftCredential?) -> OAuth2Swift {
        let oauth = OAuth2Swift(consumerKey: Secrets.shared.value(for: "flysto.consumerKey"),
                                consumerSecret: Secrets.shared.value(for: "flysto.consumerSecret"),
                                authorizeUrl: Secrets.shared.value(for: "flysto.authorizeUrl"),
                                accessTokenUrl: Secrets.shared.value(for: "flysto.accessTokenUrl"),
                                responseType: "code")
        // a state is sent and checked when FlySto returns it
        oauth.allowMissingStateCheck = true
        if let credential = credential {
            oauth.client.credential.oauthToken = credential.oauthToken
            oauth.client.credential.oauthTokenSecret = credential.oauthTokenSecret
            oauth.client.credential.oauthRefreshToken = credential.oauthRefreshToken
            oauth.client.credential.oauthTokenExpiresAt = credential.oauthTokenExpiresAt
        }
        return oauth
    }

    private static func post(client : OAuthSwiftClient, url : URL, body : Data) async throws -> OAuthSwiftResponse {
        return try await withCheckedThrowingContinuation { continuation in
            client.post(url, body: body) { result in
                continuation.resume(with: result)
            }
        }
    }

    private static func get(client : OAuthSwiftClient, url : URL) async throws -> OAuthSwiftResponse {
        return try await withCheckedThrowingContinuation { continuation in
            client.get(url) { result in
                continuation.resume(with: result)
            }
        }
    }

    //MARK: - Errors

    enum Outcome : Equatable {
        /// maybe an expired token: refresh once and try again
        case refreshAndRetry(Int)
        case duplicate(String?)
        case transient(String)
        case permanent(String)

        /// - Parameter retried: already refreshed once; an auth error now means sign in
        func failure(retried : Bool) -> UploadFailure {
            switch self {
            case .refreshAndRetry(let status):
                // still refused with a fresh token: 401/403 is the credential, 503 the server
                if status == 503 {
                    return .transient("FlySto unavailable (503)")
                }
                return retried ? .auth("FlySto refused the sign in (\(status))") : .transient("FlySto token expired")
            case .duplicate(let body):
                return .duplicate(UploadReceipt(response: FlyStoService.fileIdResponse(body)))
            case .transient(let message):
                return .transient(message)
            case .permanent(let message):
                return .permanent(message)
            }
        }
    }

    /// What to do about an HTTP status (U3: a 400 is this file's problem, it never signs out).
    static func classify(status : Int, body : String?) -> Outcome {
        switch status {
        case 401, 403:
            return .refreshAndRetry(status)
        case 503:
            // FlySto has answered 503 to an expired token
            return .refreshAndRetry(status)
        case 409:
            return .duplicate(body)
        case 408, 429, 500...599:
            return .transient("FlySto error \(status)")
        default:
            let detail = body.map { ": \($0.prefix(200))" } ?? ""
            return .permanent("FlySto refused the file (\(status))\(detail)")
        }
    }

    static func classify(_ error : OAuthSwiftError) -> Outcome {
        switch error {
        case .tokenExpired, .accessDenied, .missingToken:
            return .refreshAndRetry(401)
        case .requestError(let underlying, _):
            let nsError = underlying as NSError
            if nsError.domain == OAuthSwiftError.Domain, nsError.code >= 400 {
                return Self.classify(status: nsError.code, body: nsError.userInfo["Response-Body"] as? String)
            }
            // network: offline, timeout, DNS
            return .transient(nsError.localizedDescription)
        default:
            return .transient(error.localizedDescription)
        }
    }

    //MARK: - Upload file

    /// The log zipped in a temporary folder, read and removed (U7: no archive left
    /// beside the logs, where iCloud would sync it).
    static func zip(_ file : URL) throws -> Data {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("flysto-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let archiveUrl = folder.appendingPathComponent(file.lastPathComponent).appendingPathExtension("zip")
            guard let archive = Archive(url: archiveUrl, accessMode: .create) else {
                throw UploadFailure.permanent("Could not create the archive for \(file.lastPathComponent)")
            }
            try archive.addEntry(with: file.lastPathComponent, fileURL: file, compressionMethod: .deflate)
            return try Data(contentsOf: archiveUrl)
        }catch let failure as UploadFailure {
            throw failure
        }catch{
            throw UploadFailure.permanent("Could not read \(file.lastPathComponent): \(error.localizedDescription)")
        }
    }

    struct UploadResponse : Codable {
        var fileId : String
    }

    /// The response kept only if it carries a file id.
    static func fileIdResponse(_ response : String?) -> String? {
        return Self.fileId(from: response) != nil ? response : nil
    }

    static func fileId(from response : String?) -> String? {
        guard let data = response?.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(UploadResponse.self, from: data) else { return nil }
        return decoded.fileId
    }
}

/// Sign in to FlySto in an `ASWebAuthenticationSession`, only ever started by the user.
@MainActor
final class FlyStoSignIn : NSObject, ASWebAuthenticationPresentationContextProviding {
    private var oauth : OAuth2Swift? = nil
    private weak var anchor : UIWindow? = nil

    /// - Parameter window: the window to present the sign in page over
    func signIn(from window : UIWindow?) async throws {
        self.anchor = window
        let oauth = FlyStoService.makeOAuth(credential: nil)
        let callback = Secrets.shared.value(for: "flysto.callbackUrl")
        let scheme = URL(string: callback)?.scheme ?? "flightlogstats"
        oauth.authorizeURLHandler = ASWebAuthenticationURLHandler(callbackUrlScheme: scheme, presentationContextProvider: self)
        self.oauth = oauth
        defer { self.oauth = nil }
        let state = UUID().uuidString
        let _ : OAuthSwift.TokenSuccess = try await withCheckedThrowingContinuation { continuation in
            oauth.authorize(withCallbackURL: URL(string: callback), scope: "", state: state) { result in
                continuation.resume(with: result)
            }
        }
        await FlyStoService.shared.signedIn(oauth.client.credential)
        Logger.net.info("Signed in to FlySto")
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return MainActor.assumeIsolated {
            if let anchor = self.anchor {
                return anchor
            }
            // sign in is started from a screen: there is a window scene
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
            return scene.keyWindow ?? UIWindow(windowScene: scene)
        }
    }
}
