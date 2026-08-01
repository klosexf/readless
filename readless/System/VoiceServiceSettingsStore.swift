import Foundation

@MainActor
final class VoiceServiceSettingsStore: VoiceServiceConfigurationStoring {
    private enum Keys {
        static let configuration = "voice-service-configuration-v1"
        static let onboardingCompleted = "voice-service-onboarding-completed-v1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var configuration: VoiceServiceConfiguration? {
        guard let data = defaults.data(forKey: Keys.configuration) else {
            return nil
        }
        return try? decoder.decode(VoiceServiceConfiguration.self, from: data)
    }

    var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: Keys.onboardingCompleted)
    }

    func save(configuration: VoiceServiceConfiguration) throws {
        defaults.set(
            try encoder.encode(configuration),
            forKey: Keys.configuration
        )
    }

    func setHasCompletedOnboarding(_ completed: Bool) {
        defaults.set(completed, forKey: Keys.onboardingCompleted)
    }
}
