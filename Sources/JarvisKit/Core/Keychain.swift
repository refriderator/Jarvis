import Foundation
import Security

/// Secrets as generic passwords in the login Keychain.
public struct KeychainStore: SecretStore {
    public let service: String

    public init(service: String = "io.github.jarvis-public") {
        self.service = service
    }

    public func get(_ key: SecretKey) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ key: SecretKey, _ value: String?) {
        SecItemDelete(baseQuery(key) as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var item = baseQuery(key)
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    private func baseQuery(_ key: SecretKey) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key.rawValue]
    }
}
