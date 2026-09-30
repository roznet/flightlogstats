//
//  Keychain.swift
//  FlightLogStats
//
//  Generic passwords for service tokens: UserDefaults is backed up in clear.
//

import Foundation
import Security
import OSLog

struct KeychainStore : Sendable {
    let service : String

    private func query(_ account : String) -> [String:Any] {
        return [
            kSecClass as String : kSecClassGenericPassword,
            kSecAttrService as String : self.service,
            kSecAttrAccount as String : account,
        ]
    }

    func data(for account : String) -> Data? {
        var query = self.query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item : CFTypeRef? = nil
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                Logger.net.error("Keychain read \(account) failed \(status)")
            }
            return nil
        }
        return item as? Data
    }

    /// Store, or delete when `data` is nil. Device only (not synced): each device signs
    /// in once, so two devices never refresh the same token.
    @discardableResult
    func set(_ data : Data?, for account : String) -> Bool {
        let query = self.query(account)
        guard let data = data else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let attributes : [String:Any] = [
            kSecValueData as String : data,
            kSecAttrAccessible as String : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
        if status != errSecSuccess {
            Logger.net.error("Keychain write \(account) failed \(status)")
        }
        return status == errSecSuccess
    }
}
