import Foundation
import Security

enum KeychainCredentialStoreError: Error {
    case unexpectedStatus(OSStatus)
}

@MainActor
final class KeychainCredentialStore: VoiceServiceCredentialStoring {
    private let service: String

    init(service: String = "com.xiaofengchen.readless.voice-credentials.v1") {
        self.service = service
    }

    func hasCredential(for slot: VoiceCredentialSlot) -> Bool {
        (try? credential(for: slot))?.isEmpty == false
    }

    func credential(for slot: VoiceCredentialSlot) throws -> String? {
        if let credential = try credentialInKeychain(for: slot) {
            return credential
        }
        if slot == .doubaoV1 {
            return try credentialInKeychain(for: .doubaoLegacy)
        }
        return nil
    }

    func saveCredential(
        _ credential: String,
        for slot: VoiceCredentialSlot
    ) throws {
        let data = Data(credential.utf8)
        let status = SecItemUpdate(
            itemQuery(for: slot) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecSuccess {
            return
        }
        guard status == errSecItemNotFound else {
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
        let item = itemQuery(for: slot).merging([
            kSecValueData as String: data
        ]) { _, new in new }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainCredentialStoreError.unexpectedStatus(addStatus)
        }
    }

    func removeCredential(for slot: VoiceCredentialSlot) throws {
        let status = SecItemDelete(itemQuery(for: slot) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
    }

    private func credentialInKeychain(
        for slot: VoiceCredentialSlot
    ) throws -> String? {
        let query = itemQuery(for: slot).merging([
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

    private func itemQuery(for slot: VoiceCredentialSlot) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: slot.rawValue
        ]
    }
}
