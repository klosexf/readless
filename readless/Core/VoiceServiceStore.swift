import Foundation

@MainActor
protocol VoiceServiceReadinessChecking {
    var isReadyForSpeech: Bool { get }
}

@MainActor
protocol VoiceServiceConfigurationStoring {
    var configuration: VoiceServiceConfiguration? { get }
}

@MainActor
protocol VoiceServiceCredentialChecking {
    func hasCredential(for provider: VoiceProviderKind) -> Bool
}

@MainActor
protocol VoiceServiceCredentialStoring: VoiceServiceCredentialChecking {
    func credential(for provider: VoiceProviderKind) throws -> String?
    func saveCredential(_ credential: String, for provider: VoiceProviderKind) throws
    func removeCredential(for provider: VoiceProviderKind) throws
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
        return credentials.hasCredential(for: configuration.provider)
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
