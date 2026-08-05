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
            return persistedStateMatches(
                configuration,
                expectedCredential: newCredential.isEmpty
                    ? nil
                    : newCredential
            )
                ? nil
                : .persistenceFailed
        }
    }

    private func persistedStateMatches(
        _ configuration: VoiceServiceConfiguration,
        expectedCredential: String?
    ) -> Bool {
        guard settings.configuration == configuration else {
            return false
        }
        if let expectedCredential {
            return (try? credentials.credential(
                for: configuration.credentialSlot
            )) == expectedCredential
        }
        return credentials.hasCredential(
            for: configuration.credentialSlot
        )
    }
}
