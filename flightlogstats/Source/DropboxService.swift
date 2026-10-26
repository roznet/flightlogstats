//
//  DropboxService.swift
//  FlightLogStats
//
//  Dropbox: each flight's summary JSON saved in the app folder (Apps/<app name>/flights),
//  where other tools read it. PKCE sign in (no client secret), token refresh, upload.
//

import Foundation
import AuthenticationServices
import CryptoKit
import OSLog
import UIKit
import RZUtilsSwift

extension RemoteServiceRecord.Status : Codable {}

actor DropboxService : UploadService {
    static let shared = DropboxService()

    /// Folder inside the app folder the summaries are saved to.
    static let folder = "/flights"
    static let authorizeUrl = "https://www.dropbox.com/oauth2/authorize"
    static let tokenUrl = "https://api.dropboxapi.com/oauth2/token"
    static let uploadUrl = "https://content.dropboxapi.com/2/files/upload"

    struct Credential : Codable, Equatable {
        var accessToken : String
        var refreshToken : String
        var expiresAt : Date

        func isExpired(now : Date = Date()) -> Bool {
            // a minute of margin for the request itself
            return now.addingTimeInterval(60) >= self.expiresAt
        }
    }

    /// The file to save for a log: its name in the app folder and its content.
    typealias Content = @Sendable (URL) async throws -> (name : String, data : Data)

    private let keychain : KeychainStore
    private let isEnabled : @Sendable () -> Bool
    private let content : Content
    private let session : URLSession
    private var credential : Credential? = nil
    /// set when Dropbox rejected the credential: only a sign in clears it
    private var rejected : Bool = false
    /// one refresh at a time: concurrent callers wait for the same one
    private var refreshTask : Task<Void,Error>? = nil

    static let credentialAccount = "credential"

    init(keychain : KeychainStore = KeychainStore(service: "net.ro-z.flightlogstats.dropbox"),
         isEnabled : @escaping @Sendable () -> Bool = { Settings.shared.dropboxEnabled },
         session : URLSession = .shared,
         content : @escaping Content = DropboxService.summaryContent) {
        self.keychain = keychain
        self.isEnabled = isEnabled
        self.session = session
        self.content = content
        if let data = keychain.data(for: Self.credentialAccount) {
            self.credential = try? JSONDecoder().decode(Credential.self, from: data)
        }
    }

    static var appKey : String { return Secrets.shared["dropbox.appKey"] ?? "" }
    /// The scheme Dropbox accepts for an app key without registering a redirect URI.
    static var redirectUri : String { return "db-\(Self.appKey)://2/token" }

    /// The summary JSON of a log, built from a full parse on the worker.
    static let summaryContent : Content = { file in
        let name = file.lastPathComponent
        let export : FlightSummaryExport? = await withCheckedContinuation { continuation in
            AppDelegate.worker.async {
                guard let record = FlightLogOrganizer.shared[name] else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: FlightSummaryExport.make(record: record, folder: file.deletingLastPathComponent()))
            }
        }
        guard let export = export else {
            throw UploadFailure.permanent("No flight data in \(name)")
        }
        do {
            return (export.fileName, try export.json())
        }catch{
            throw UploadFailure.permanent("Could not write the summary of \(name): \(error.localizedDescription)")
        }
    }

    //MARK: - Credential

    private func save(_ credential : Credential?) {
        self.credential = credential
        if let credential = credential, let data = try? JSONEncoder().encode(credential) {
            self.keychain.set(data, for: Self.credentialAccount)
        }else{
            self.keychain.set(nil, for: Self.credentialAccount)
        }
    }

    var hasCredential : Bool { return self.credential != nil }

    func signOut() {
        self.save(nil)
        self.rejected = false
    }

    func signedIn(_ credential : Credential) {
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
            throw UploadFailure.auth("Sign in to Dropbox")
        }
        let (name, data) = try await self.content(file)
        let path = "\(Self.folder)/\(name)"
        try await self.authorized { token in
            try await self.post(path: path, data: data, token: token)
        }
        return UploadReceipt(response: path)
    }

    //MARK: - Requests

    /// Run a request with a valid token: refresh first if expired, and once more after a
    /// 401. Never opens a sign in page.
    private func authorized(_ request : (String) async throws -> Void) async throws {
        guard let credential = self.credential, !self.rejected else {
            throw UploadFailure.auth("Sign in to Dropbox")
        }
        if credential.isExpired() {
            try await self.refresh()
        }
        do {
            try await request(self.credential?.accessToken ?? "")
        }catch Outcome.refreshAndRetry {
            Logger.net.info("Dropbox answered 401, refreshing the token and trying again")
            try await self.refresh()
            do {
                try await request(self.credential?.accessToken ?? "")
            }catch Outcome.refreshAndRetry {
                self.rejected = true
                throw UploadFailure.auth("Dropbox refused the sign in")
            }
        }
    }

    private func post(path : String, data : Data, token : String) async throws {
        guard let url = URL(string: Self.uploadUrl) else {
            throw UploadFailure.permanent("Invalid Dropbox upload URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(try Self.apiArg(path: path), forHTTPHeaderField: "Dropbox-API-Arg")
        request.httpBody = data
        let (body, response) = try await self.send(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status != 200 else { return }
        switch Self.classify(status: status, body: String(data: body, encoding: .utf8)) {
        case .refreshAndRetry:
            throw Outcome.refreshAndRetry
        case .transient(let message):
            throw UploadFailure.transient(message)
        case .permanent(let message):
            throw UploadFailure.permanent(message)
        }
    }

    /// A network error (offline, timeout) is transient.
    private func send(_ request : URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await self.session.data(for: request)
        }catch{
            throw UploadFailure.transient(error.localizedDescription)
        }
    }

    /// The upload arguments: overwrite, so saving a log again replaces its summary; mute,
    /// so the Dropbox apps do not notify each save.
    static func apiArg(path : String) throws -> String {
        struct Arg : Encodable {
            let path : String
            let mode = "overwrite"
            let autorename = false
            let mute = true
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(Arg(path: path))
        // the header must be ASCII: escape anything else as JSON does (UTF-16 units)
        var header = ""
        for unit in String(decoding: data, as: UTF8.self).utf16 {
            if unit < 0x80, let scalar = Unicode.Scalar(unit) {
                header.unicodeScalars.append(scalar)
            }else{
                header += String(format: "\\u%04x", unit)
            }
        }
        return header
    }

    //MARK: - Token

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
        guard let current = self.credential else {
            self.rejected = true
            throw UploadFailure.auth("Sign in to Dropbox")
        }
        Logger.net.info("Refreshing Dropbox token")
        let request = Self.tokenRequest(["grant_type" : "refresh_token",
                                         "refresh_token" : current.refreshToken,
                                         "client_id" : Self.appKey])
        let (body, response) = try await self.send(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            guard let token = try? JSONDecoder().decode(TokenResponse.self, from: body) else {
                throw UploadFailure.transient("Unexpected Dropbox token answer")
            }
            // a refresh answer has no new refresh token: keep the one we have
            self.save(token.credential(refreshToken: current.refreshToken))
        case 408, 429, 500...599:
            throw UploadFailure.transient("Dropbox error \(status)")
        default:
            // 400 invalid_grant: the refresh token was revoked
            Logger.net.error("Dropbox refresh refused \(status)")
            self.rejected = true
            throw UploadFailure.auth("Dropbox sign in expired")
        }
    }

    struct TokenResponse : Decodable {
        let access_token : String
        let expires_in : Double
        let refresh_token : String?

        func credential(refreshToken : String? = nil, now : Date = Date()) -> Credential? {
            guard let refresh = self.refresh_token ?? refreshToken else { return nil }
            return Credential(accessToken: self.access_token, refreshToken: refresh,
                              expiresAt: now.addingTimeInterval(self.expires_in))
        }
    }

    static func tokenRequest(_ form : [String:String]) -> URLRequest {
        var request = URLRequest(url: URL(string: Self.tokenUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // encode all but the unreserved characters: '+' would read as a space
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let body = form.keys.sorted().map { key in
            let value = form[key]?.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(key)=\(value)"
        }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        return request
    }

    /// Exchange the code from the sign in page for tokens.
    func exchange(code : String, verifier : String) async throws {
        let request = Self.tokenRequest(["grant_type" : "authorization_code",
                                         "code" : code,
                                         "code_verifier" : verifier,
                                         "client_id" : Self.appKey,
                                         "redirect_uri" : Self.redirectUri])
        let (body, response) = try await self.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200,
              let token = try? JSONDecoder().decode(TokenResponse.self, from: body),
              let credential = token.credential() else {
            let detail = String(data: body, encoding: .utf8).map { ": \($0.prefix(200))" } ?? ""
            throw UploadFailure.auth("Dropbox sign in failed (\(status))\(detail)")
        }
        self.signedIn(credential)
    }

    //MARK: - Errors

    enum Outcome : Error, Equatable {
        /// maybe an expired token: refresh once and try again
        case refreshAndRetry
        case transient(String)
        case permanent(String)
    }

    /// What to do about an HTTP status of an upload.
    static func classify(status : Int, body : String?) -> Outcome {
        switch status {
        case 401:
            return .refreshAndRetry
        case 408, 429, 500...599:
            return .transient("Dropbox error \(status)")
        default:
            // 400 bad request, 403 no access to the folder, 409 a path error (no space, ...)
            let detail = body.map { ": \($0.prefix(200))" } ?? ""
            return .permanent("Dropbox refused the file (\(status))\(detail)")
        }
    }
}

/// Sign in to Dropbox in an `ASWebAuthenticationSession` (PKCE: the app has no secret),
/// only ever started by the user.
@MainActor
final class DropboxSignIn : NSObject, ASWebAuthenticationPresentationContextProviding {
    private weak var anchor : UIWindow? = nil
    private var session : ASWebAuthenticationSession? = nil

    enum SignInError : Error, LocalizedError {
        case noAppKey
        case invalidAnswer
        case refused(String)

        var errorDescription : String? {
            switch self {
            case .noAppKey: return "No Dropbox app key configured (dropbox.appKey in secrets.json)"
            case .invalidAnswer: return "Unexpected answer from the Dropbox sign in page"
            case .refused(let message): return message
            }
        }
    }

    /// - Parameter window: the window to present the sign in page over
    func signIn(from window : UIWindow?) async throws {
        guard !DropboxService.appKey.isEmpty else { throw SignInError.noAppKey }
        self.anchor = window
        let verifier = Self.randomString()
        let state = UUID().uuidString
        var components = URLComponents(string: DropboxService.authorizeUrl)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: DropboxService.appKey),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            // a refresh token, so the sign in lasts
            URLQueryItem(name: "token_access_type", value: "offline"),
            URLQueryItem(name: "redirect_uri", value: DropboxService.redirectUri),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else { throw SignInError.invalidAnswer }
        let scheme = "db-\(DropboxService.appKey)"

        let callback : URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { url, error in
                if let url = url {
                    continuation.resume(returning: url)
                }else{
                    continuation.resume(throwing: error ?? SignInError.invalidAnswer)
                }
            }
            session.presentationContextProvider = self
            self.session = session
            session.start()
        }
        self.session = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error_description" || $0.name == "error" })?.value {
            throw SignInError.refused("Dropbox sign in: \(error)")
        }
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw SignInError.invalidAnswer
        }
        do {
            try await DropboxService.shared.exchange(code: code, verifier: verifier)
        }catch let failure as UploadFailure {
            throw SignInError.refused(failure.reason)
        }
        Logger.net.info("Signed in to Dropbox")
    }

    /// PKCE verifier: 43 to 128 characters of [A-Za-z0-9-._~].
    nonisolated static func randomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Self.base64url(Data(bytes))
    }

    nonisolated static func challenge(for verifier : String) -> String {
        return Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    nonisolated static func base64url(_ data : Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
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

/// An upload queue kept in a JSON file on this device. For Dropbox the state need not
/// sync: an upload overwrites, so a second device saving a summary again is harmless.
actor FileUploadStore : UploadStore {
    struct Entry : Codable, Equatable {
        var status : RemoteServiceRecord.Status = .ready
        var attempts : Int = 0
        var lastError : String? = nil
        var nextRetry : Date? = nil
        var date : Date? = nil
        var receipt : String? = nil
    }

    let url : URL
    private let folder : @Sendable () -> URL
    private var entries : [String:Entry]

    /// - Parameters:
    ///   - url: the JSON file of the queue
    ///   - folder: where the logs are
    init(url : URL, folder : @escaping @Sendable () -> URL) {
        self.url = url
        self.folder = folder
        if let data = try? Data(contentsOf: url),
           let entries = try? JSONDecoder().decode([String:Entry].self, from: data) {
            self.entries = entries
        }else{
            self.entries = [:]
        }
    }

    static func defaultUrl(name : String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent(name)
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(self.entries)
            try data.write(to: self.url, options: .atomic)
        }catch{
            Logger.net.error("Could not save the upload queue \(self.url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func entry(_ name : String) -> Entry? {
        return self.entries[name]
    }

    var all : [String:Entry] { return self.entries }

    //MARK: - UploadStore

    func queue(_ names : [String], force : Bool) -> [String] {
        var queued : [String] = []
        for name in names {
            var entry = self.entries[name] ?? Entry()
            if !force && entry.status == .uploaded { continue }
            entry.status = .pending
            entry.date = Date()
            entry.attempts = 0
            entry.lastError = nil
            entry.nextRetry = nil
            self.entries[name] = entry
            queued.append(name)
        }
        if !queued.isEmpty {
            self.persist()
        }
        return queued
    }

    func due(now : Date) -> [UploadJob] {
        let folder = self.folder()
        // log names start with their date: newest first
        return self.entries.keys.sorted(by: >).compactMap { name in
            guard let entry = self.entries[name] else { return nil }
            let isDue : Bool
            switch entry.status {
            case .pending:
                isDue = true
            case .failed:
                isDue = entry.nextRetry.map { $0 <= now } ?? false
            case .ready, .uploaded:
                isDue = false
            }
            guard isDue else { return nil }
            let file = folder.appendingPathComponent(name)
            // a log still in iCloud waits for its download
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            return UploadJob(name: name, file: file, attempts: entry.attempts)
        }
    }

    func nextRetry() -> Date? {
        return self.entries.values.filter { $0.status == .failed }.compactMap { $0.nextRetry }.min()
    }

    func markUploaded(_ name : String, receipt : UploadReceipt) {
        var entry = self.entries[name] ?? Entry()
        entry.status = .uploaded
        entry.date = Date()
        entry.lastError = nil
        entry.nextRetry = nil
        entry.receipt = receipt.response
        self.entries[name] = entry
        self.persist()
        NotificationCenter.default.post(name: .newFileUploaded, object: name)
    }

    func markFailed(_ name : String, reason : String, attempts : Int, nextRetry : Date?) {
        var entry = self.entries[name] ?? Entry()
        entry.status = .failed
        entry.date = Date()
        entry.attempts = attempts
        entry.lastError = reason
        entry.nextRetry = nextRetry
        self.entries[name] = entry
        self.persist()
        NotificationCenter.default.post(name: .newFileUploaded, object: name)
    }

    func failed() -> [String] {
        return self.entries.filter { $0.value.status == .failed }.map { $0.key }
    }
}
