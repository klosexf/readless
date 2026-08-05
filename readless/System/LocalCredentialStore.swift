import Foundation

enum LocalCredentialStoreError: Error {
    case invalidFile
    case persistenceFailed
}

@MainActor
final class LocalCredentialStore: VoiceServiceCredentialStoring {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        self.fileURL = fileURL ?? applicationSupport
            .appendingPathComponent("Readless", isDirectory: true)
            .appendingPathComponent("voice-credentials-v1.json")
    }

    func hasCredential(for slot: VoiceCredentialSlot) -> Bool {
        (try? credential(for: slot))?.isEmpty == false
    }

    func credential(for slot: VoiceCredentialSlot) throws -> String? {
        try load()[slot.rawValue]
    }

    func saveCredential(
        _ credential: String,
        for slot: VoiceCredentialSlot
    ) throws {
        var values = try load()
        values[slot.rawValue] = credential
        try persist(values)
    }

    func removeCredential(for slot: VoiceCredentialSlot) throws {
        var values = try load()
        values.removeValue(forKey: slot.rawValue)
        try persist(values)
    }

    private func load() throws -> [String: String] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        do {
            return try decoder.decode(
                [String: String].self,
                from: Data(contentsOf: fileURL)
            )
        } catch {
            throw LocalCredentialStoreError.invalidFile
        }
    }

    private func persist(_ values: [String: String]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            // 权限设置是尽力而为：即使当前进程因为文件所有者等原因
            // 无法修改权限，也不应阻止凭据内容本身被写入。
            try? fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directoryURL.path
            )
            try encoder.encode(values).write(to: fileURL, options: .atomic)
            try? fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            throw LocalCredentialStoreError.persistenceFailed
        }
    }
}
