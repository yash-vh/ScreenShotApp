import Foundation
import Security

/// Storage for secrets (S3 keys, upload delete tokens). Abstracted so tests never touch the real Keychain.
public protocol SecretStore: Sendable {
    func set(_ value: String, for account: String) throws
    func value(for account: String) throws -> String?
    func remove(_ account: String)
}

/// Generic-password items in the user's login Keychain, scoped to this app's service name
public struct KeychainStore: SecretStore {
    public static let shared = KeychainStore()

    public enum Account {
        public static let s3AccessKeyID = "s3.accessKeyID"
        public static let s3SecretAccessKey = "s3.secretAccessKey"
        public static let imgbbAPIKey = "imgbb.apiKey"
        public static func deleteToken(for recordId: UUID) -> String { "upload.deleteToken.\(recordId.uuidString)" }
    }

    private let service: String

    public init(service: String = "com.screenmint.mac.credentials") {
        self.service = service
    }

    private func baseQuery(_ account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }

    public func set(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw AppError.keychainSaveFailed(status: addStatus) }
        } else if status != errSecSuccess {
            throw AppError.keychainSaveFailed(status: status)
        }
    }

    public func value(for account: String) throws -> String? {
        var query = baseQuery(account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw AppError.keychainReadFailed(status: status) }
        return String(data: data, encoding: .utf8)
    }

    public func remove(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}

/// In-memory secret store for tests and previews
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func set(_ value: String, for account: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[account] = value
    }

    public func value(for account: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[account]
    }

    public func remove(_ account: String) {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: account)
    }
}
