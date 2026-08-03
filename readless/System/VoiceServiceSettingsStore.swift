import Foundation

@MainActor
final class VoiceServiceSettingsStore: VoiceServiceConfigurationStoring {
    private enum Keys {
        static let configuration = "voice-service-configuration-v1"
        static let profiles = "voice-service-profiles-v2"
        static let onboardingCompleted = "voice-service-onboarding-completed-v1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var configuration: VoiceServiceConfiguration? {
        profiles.activeConfiguration
    }

    var profiles: VoiceServiceProfiles {
        if let data = defaults.data(forKey: Keys.profiles),
           let profiles = try? decoder.decode(
               VoiceServiceProfiles.self,
               from: data
           ) {
            return profiles
        }

        guard let data = defaults.data(forKey: Keys.configuration),
              let configuration = try? decoder.decode(
                  VoiceServiceConfiguration.self,
                  from: data
              )
        else {
            return VoiceServiceProfiles()
        }
        return VoiceServiceProfiles.migrated(from: configuration)
    }

    var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: Keys.onboardingCompleted)
    }

    func save(configuration: VoiceServiceConfiguration) throws {
        var profiles = profiles
        profiles.save(configuration)
        try save(profiles: profiles)
    }

    func selectDoubaoVersion(_ version: DoubaoAPIVersion) {
        var profiles = profiles
        profiles.selectDoubaoVersion(version)
        try? save(profiles: profiles)
    }

    func setHasCompletedOnboarding(_ completed: Bool) {
        defaults.set(completed, forKey: Keys.onboardingCompleted)
    }

    private func save(profiles: VoiceServiceProfiles) throws {
        defaults.set(try encoder.encode(profiles), forKey: Keys.profiles)
    }
}
