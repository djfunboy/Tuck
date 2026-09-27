import Foundation
import Security

protocol CredentialWriting: Sendable {
    func save(_ value: Data, for request: CredentialRequest, replace: Bool) throws
}

enum KeychainError: Error, Equatable {
    case emptyValue
    case valueTooLarge
    case duplicate
    case unavailable(OSStatus)
}

struct KeychainWriter: CredentialWriting {
    static let maximumValueBytes = 65_536

    func save(_ value: Data, for request: CredentialRequest, replace: Bool) throws {
        guard !value.isEmpty else { throw KeychainError.emptyValue }
        guard value.count <= Self.maximumValueBytes else { throw KeychainError.valueTooLarge }
        let query = Self.query(for: request)
        var attributes = query
        attributes[kSecValueData as String] = value
        attributes[kSecAttrLabel as String] = request.service
        // The existing login Keychain is compatible with ordinary CLI consumers.
        // Do not widen the default ACL, enable sync, or save outside Keychain.
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            guard replace else { throw KeychainError.duplicate }
            let update = [kSecValueData as String: value]
            let result = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard result == errSecSuccess else { throw KeychainError.unavailable(result) }
        } else if status != errSecSuccess {
            throw KeychainError.unavailable(status)
        }
    }

    static func query(for request: CredentialRequest) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: request.service,
         kSecAttrAccount as String: request.account,
         kSecUseDataProtectionKeychain as String: false]
    }
}
