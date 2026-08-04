import Foundation

@MainActor
final class VoiceServiceSaveCoordinator {
    private let settings: VoiceServiceSettingsSaving
    private let credentials: VoiceServiceCredentialStoring

    init(
        settings: VoiceServiceSettingsSaving,
        credentials: VoiceServiceCredentialStoring
    ) {
        self.settings = settings
        self.credentials = credentials
    }

    func save(
        configuration: VoiceServiceConfiguration,
        credential: String
    ) -> VoiceServiceSaveError? {
        let newCredential = credential.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let validationError = configuration.validationError {
            return .validation(validationError)
        }

        do {
            if !newCredential.isEmpty {
                if let error = VoiceServiceConfigurationValidator.saveError(
                    for: configuration.provider,
                    configuration: configuration,
                    credential: newCredential
                ) {
                    return error
                }
                try credentials.saveCredential(
                    newCredential,
                    for: configuration.credentialSlot
                )
            }
            try settings.save(configuration: configuration)
            return nil
        } catch {
            return persistedStateMatches(configuration)
                ? nil
                : .persistenceFailed
        }
    }

    private func persistedStateMatches(
        _ configuration: VoiceServiceConfiguration
    ) -> Bool {
        settings.configuration == configuration
            && credentials.hasCredential(
                for: configuration.credentialSlot
            )
    }
}
