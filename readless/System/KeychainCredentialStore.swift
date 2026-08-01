import Foundation
import Security

enum KeychainCredentialStoreError: Error {
    case unexpectedStatus(OSStatus)
}

@MainActor
final class KeychainCredentialStore: VoiceServiceCredentialStoring {
    private let service = "com.xiaofengchen.readless.voice-credentials.v1"

    func hasCredential(for provider: VoiceProviderKind) -> Bool {
        (try? credential(for: provider))?.isEmpty == false
    }

    func credential(for provider: VoiceProviderKind) throws -> String? {
        let query = itemQuery(for: provider).merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]) { _, new in new }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let credential = String(data: data, encoding: .utf8)
        else {
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
        return credential
    }

    func saveCredential(
        _ credential: String,
        for provider: VoiceProviderKind
    ) throws {
        let data = Data(credential.utf8)
        let status = SecItemUpdate(
            itemQuery(for: provider) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecSuccess {
            return
        }
        guard status == errSecItemNotFound else {
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
        let item = itemQuery(for: provider).merging([
            kSecValueData as String: data
        ]) { _, new in new }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainCredentialStoreError.unexpectedStatus(addStatus)
        }
    }

    func removeCredential(for provider: VoiceProviderKind) throws {
        let status = SecItemDelete(itemQuery(for: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
    }

    private func itemQuery(for provider: VoiceProviderKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
    }
}
