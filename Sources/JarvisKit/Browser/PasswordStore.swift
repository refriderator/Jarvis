import Foundation
import Security

/// A sign-in saved from the Web tab.
public struct SavedLogin: Equatable, Sendable {
    public var host: String
    public var username: String
    public var password: String

    public init(host: String, username: String, password: String) {
        self.host = host
        self.username = username
        self.password = password
    }
}

/// Whether a site is one where saving a password is safe for anyone: a real public website over https on the
/// standard port. Not a bare IP address, a local name ("localhost", "printer.local", "router"), or an odd port,
/// where the same name can be a different machine on another network.
public enum PasswordSafety {
    public static func allows(host: String, port: Int) -> Bool {
        let host = host.lowercased()
        guard port == 0 || port == 443, host.contains("."), !host.hasSuffix("."),
              !host.hasSuffix(".local"), !host.hasSuffix(".localhost"), !host.hasSuffix(".internal"),
              !host.hasSuffix(".lan"), !host.hasSuffix(".home.arpa"), host != "localhost" else { return false }
        // IPv4 (all digits and dots) or IPv6 (has a colon).
        if host.contains(":") || host.allSatisfy({ $0.isNumber || $0 == "." }) { return false }
        return true
    }
}

/// The Web tab's saved passwords, in the login Keychain as internet passwords (Keychain Access lists them under
/// the site's address). Only this app can read them back without the Mac asking.
public enum PasswordStore {
    /// Every saved sign-in for exactly this host ("accounts.google.com", not "google.com").
    /// The Mac's file-based Keychain won't return every item's password in one search, so the usernames come first,
    /// then each password.
    public static func logins(for host: String) -> [SavedLogin] {
        var query = base(host: host)
        query[kSecMatchLimit] = kSecMatchLimitAll
        query[kSecReturnAttributes] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[CFString: Any]] else { return [] }
        return items.compactMap { item in
            let username = item[kSecAttrAccount] as? String ?? ""
            var one = base(host: host)
            one[kSecAttrAccount] = username
            one[kSecMatchLimit] = kSecMatchLimitOne
            one[kSecReturnData] = true
            var data: CFTypeRef?
            guard SecItemCopyMatching(one as CFDictionary, &data) == errSecSuccess, let data = data as? Data,
                  let password = String(data: data, encoding: .utf8) else { return nil }
            return SavedLogin(host: host, username: username, password: password)
        }
    }

    /// Saves it, replacing the password already saved for that host and username.
    @discardableResult public static func save(_ login: SavedLogin) -> Bool {
        var match = base(host: login.host)
        match[kSecAttrAccount] = login.username
        let data = Data(login.password.utf8)
        if SecItemUpdate(match as CFDictionary, [kSecValueData: data] as CFDictionary) == errSecSuccess { return true }
        match[kSecValueData] = data
        match[kSecAttrLabel] = login.host
        match[kSecAttrComment] = "Saved by Jarvis's Web tab"
        return SecItemAdd(match as CFDictionary, nil) == errSecSuccess
    }

    public static func delete(_ login: SavedLogin) {
        var match = base(host: login.host)
        match[kSecAttrAccount] = login.username
        SecItemDelete(match as CFDictionary)
    }

    private static func base(host: String) -> [CFString: Any] {
        [kSecClass: kSecClassInternetPassword, kSecAttrServer: host, kSecAttrProtocol: kSecAttrProtocolHTTPS]
    }
}
