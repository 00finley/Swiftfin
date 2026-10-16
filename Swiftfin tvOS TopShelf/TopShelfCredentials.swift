//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Security

/// The minimum session information the Top Shelf extension needs, shared from the app
/// through a keychain access group both targets are entitled to.
///
/// Member of both the app and the Top Shelf extension targets.
enum TopShelfCredentials {

    struct Session: Codable, Equatable {
        let serverID: String
        let serverURL: URL
        let userID: String
        let accessToken: String
    }

    private static let service = "org.jellyfin.swiftfin.topshelf"
    private static let account = "current-session"

    /// `$(AppIdentifierPrefix)org.jellyfin.swiftfin.shared`, expanded into each target's Info.plist.
    private static var accessGroup: String? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SwiftfinSharedKeychainGroup") as? String,
              group.isEmpty == false,
              group.contains("$(") == false
        else { return nil }

        return group
    }

    private static var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    @discardableResult
    static func save(_ session: Session) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }

        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> Session? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }

        return try? JSONDecoder().decode(Session.self, from: data)
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    // MARK: Diagnostics

    /// Last Top Shelf run, written by the extension and logged by the app, since the
    /// extension has no console of its own on a real Apple TV.
    private static var diagnosticsQuery: [String: Any] {
        var query = baseQuery
        query[kSecAttrAccount as String] = "last-run"
        return query
    }

    static func saveDiagnostics(_ text: String) {
        SecItemDelete(diagnosticsQuery as CFDictionary)
        var query = diagnosticsQuery
        query[kSecValueData as String] = Data(text.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func loadDiagnostics() -> String? {
        var query = diagnosticsQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }

        return String(data: data, encoding: .utf8)
    }
}
