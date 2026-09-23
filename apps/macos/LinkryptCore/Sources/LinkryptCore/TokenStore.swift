import Foundation
import Security

/// Errors from Keychain operations. Kept separate from `APIError` so Keychain
/// failures are never confused with HTTP/network errors.
public enum KeychainError: Error, Equatable {
    case unhandled(OSStatus)
}

public protocol TokenStore {
    func save(token: String, account: String) throws
    func read(account: String) -> String?
    func delete(account: String) throws
}

/// For tests + previews.
public final class InMemoryTokenStore: TokenStore {
    private var items: [String: String] = [:]
    public init() {}
    public func save(token: String, account: String) throws { items[account] = token }
    public func read(account: String) -> String? { items[account] }
    public func delete(account: String) throws { items[account] = nil }
}

/// Real macOS Keychain store. `account` is the base URL so tokens for
/// different servers don't collide. Service is the app bundle id.
public final class KeychainTokenStore: TokenStore {
    private let service: String
    public init(service: String = "sh.linkrypt.mac") { self.service = service }

    public func save(token: String, account: String) throws {
        try? delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8),
            // ThisDeviceOnly: short-lived token shouldn't sync to iCloud or migrate via backup/restore.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    public func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}
