import Foundation
import OSLog
import Security

public enum LinkCacheError: Error, Equatable {
    case wipeFailed(OSStatus)
}

// MARK: - Backing-store protocol

/// Abstraction over the persistence layer for the link cache.
/// Inject `InMemoryLinkCacheStore` in tests/previews; production
/// code uses `KeychainLinkCacheStore` (the default).
public protocol LinkCacheStore {
    func load() -> [String: String]
    func save(_ dict: [String: String])
    /// Remove the persisted blob entirely; throws on a real failure (NOT on
    /// "item not found"). Used by the failure-surfacing clear paths.
    func wipe() throws
}

// MARK: - InMemoryLinkCacheStore (tests / previews)

public final class InMemoryLinkCacheStore: LinkCacheStore {
    private var storage: [String: String] = [:]
    public init() {}
    public func load() -> [String: String] { storage }
    public func save(_ dict: [String: String]) { storage = dict }
    public func wipe() throws { storage = [:] }
}

// MARK: - KeychainLinkCacheStore (production)

/// Persists the `[id: url]` dictionary as a single JSON blob in one
/// Keychain generic-password item.
///   service:  sh.linkrypt.mac
///   account:  linkcache
///   access:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly
public final class KeychainLinkCacheStore: LinkCacheStore {
    private let service: String
    private let account: String
    private var log: Logger { Logger(subsystem: service, category: "linkcache") }

    public init(service: String = "sh.linkrypt.mac", account: String = "linkcache") {
        self.service = service
        self.account = account
    }

    public func load() -> [String: String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    public func wipe() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            log.error("keychain wipe failed: \(status, privacy: .public)")
            throw LinkCacheError.wipeFailed(status)
        }
    }

    public func save(_ dict: [String: String]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }

        let lookupQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        if dict.isEmpty {
            // Clearing the cache — delete the item if present; ignore errSecItemNotFound.
            let status = SecItemDelete(lookupQuery as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                log.error("keychain delete failed: \(status, privacy: .public)")
            }
            return
        }

        // Non-destructive upsert: try Add first; on duplicate, Update the existing item.
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        if addStatus == errSecSuccess {
            return
        }

        if addStatus == errSecDuplicateItem {
            let updateAttrs: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(lookupQuery as CFDictionary, updateAttrs as CFDictionary)
            if updateStatus != errSecSuccess {
                log.error("keychain update failed: \(updateStatus, privacy: .public)")
            }
            return
        }

        log.error("keychain add failed: \(addStatus, privacy: .public)")
    }
}

// MARK: - LinkCache

/// In-app cache mapping share id → full recipient URL (incl. #fragment), for
/// shares created on THIS device. `/api/cli/list` returns no key material, so
/// this is the only way the dashboard can offer a decryptable copy link.
///
/// Key material (AES key + IV in the URL fragment) is persisted in the Keychain
/// via `KeychainLinkCacheStore` — never in UserDefaults.
public final class LinkCache {
    private var byId: [String: String]
    private let store: any LinkCacheStore
    public private(set) var isPersistent: Bool

    public init(store: any LinkCacheStore = KeychainLinkCacheStore(), persistent: Bool = true) {
        self.store = store
        self.isPersistent = persistent
        self.byId = persistent ? store.load() : [:]
    }

    public func store(id: String, url: String) {
        byId[id] = url
        if isPersistent { store.save(byId) }
    }

    public func url(for id: String) -> String? { byId[id] }

    public func remove(id: String) {
        byId[id] = nil
        if isPersistent { store.save(byId) }
    }

    /// Clears the in-memory session (used on logout). Best-effort, non-throwing.
    public func clear() {
        byId = [:]
        if isPersistent { store.save(byId) }
    }

    /// Toggle Keychain persistence. Turning off wipes the blob (throws on
    /// failure, leaving `isPersistent == true`) but keeps the session in memory.
    /// Turning on flushes the current session to the store.
    public func setPersistent(_ persistent: Bool) throws {
        guard persistent != isPersistent else { return }
        if persistent {
            isPersistent = true
            store.save(byId)
        } else {
            try store.wipe()        // throws → state below unchanged
            isPersistent = false
        }
    }

    /// Purge BOTH the persisted blob and the in-memory session. Throws (leaving
    /// everything intact) if the wipe fails.
    public func clearAll() throws {
        try store.wipe()
        byId = [:]
    }
}
