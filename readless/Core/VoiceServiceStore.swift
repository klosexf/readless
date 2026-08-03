import Foundation

@MainActor
protocol VoiceServiceReadinessChecking {
    var isReadyForSpeech: Bool { get }
}

@MainActor
protocol VoiceServiceConfigurationStoring {
    var configuration: VoiceServiceConfiguration? { get }
    var profiles: VoiceServiceProfiles { get }
    func selectDoubaoVersion(_ version: DoubaoAPIVersion)
}

@MainActor
protocol VoiceServiceCredentialChecking {
    func hasCredential(for slot: VoiceCredentialSlot) -> Bool
}

@MainActor
protocol VoiceServiceCredentialStoring: VoiceServiceCredentialChecking {
    func credential(for slot: VoiceCredentialSlot) throws -> String?
    func saveCredential(
        _ credential: String,
        for slot: VoiceCredentialSlot
    ) throws
    func removeCredential(for slot: VoiceCredentialSlot) throws
}

@MainActor
final class StoredVoiceServiceReadiness: VoiceServiceReadinessChecking {
    private let settings: VoiceServiceConfigurationStoring
    private let credentials: VoiceServiceCredentialChecking

    init(
        settings: VoiceServiceConfigurationStoring,
        credentials: VoiceServiceCredentialChecking
    ) {
        self.settings = settings
        self.credentials = credentials
    }

    var isReadyForSpeech: Bool {
        guard
            let configuration = settings.configuration,
            configuration.validationError == nil
        else {
            return false
        }
        return credentials.hasCredential(for: configuration.credentialSlot)
    }
}

@MainActor
final class AlwaysReadyVoiceServiceReadiness:
    VoiceServiceReadinessChecking
{
    var isReadyForSpeech: Bool {
        true
    }
}
