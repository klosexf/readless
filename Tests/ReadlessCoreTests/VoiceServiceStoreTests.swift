import XCTest
@testable import ReadlessCore

@MainActor
final class VoiceServiceStoreTests: XCTestCase {
    func testReadinessRequiresValidConfigurationAndCredential() {
        let settings = VoiceServiceConfigurationStoreFake(
            configuration: .doubao(
                appID: "app-id",
                cluster: "volcano_tts",
                voiceType: "voice"
            )
        )
        let credentials = VoiceServiceCredentialStoreFake(
            savedProviders: []
        )
        let readiness = StoredVoiceServiceReadiness(
            settings: settings,
            credentials: credentials
        )

        XCTAssertFalse(readiness.isReadyForSpeech)

        credentials.savedSlots.insert(.doubaoV1)

        XCTAssertTrue(readiness.isReadyForSpeech)
    }

    func testEncodedConfigurationCannotContainCredential() throws {
        let configuration = VoiceServiceConfiguration.openAICompatible(
            baseURL: "https://tts.example",
            model: "tts-model",
            voice: "nova"
        )

        let data = try JSONEncoder().encode(configuration)
        let storedValue = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(storedValue.contains("secret-api-key"))
    }

    func testSelectingDoubaoVersionKeepsTheOtherProfile() {
        let v1 = VoiceServiceConfiguration.doubao(
            appID: "app-id",
            cluster: "volcano_tts",
            voiceType: "v1-voice"
        )
        let v3 = VoiceServiceConfiguration.doubaoV3(
            resourceID: "seed-tts-2.0",
            speaker: "v3-speaker"
        )
        var profiles = VoiceServiceProfiles(
            activeProvider: .doubao,
            activeDoubaoVersion: .v3,
            doubaoV1: v1,
            doubaoV3: v3,
            openAICompatible: nil
        )

        profiles.selectDoubaoVersion(.v1)

        XCTAssertEqual(profiles.activeConfiguration, v1)
        XCTAssertEqual(profiles.doubaoV3, v3)
    }

    func testV3ReadinessRequiresV3CredentialSlot() {
        let settings = VoiceServiceConfigurationStoreFake(
            configuration: .doubaoV3(
                resourceID: "seed-tts-2.0",
                speaker: "speaker"
            )
        )
        let credentials = VoiceServiceCredentialStoreFake(
            savedSlots: [.doubaoV1]
        )
        let readiness = StoredVoiceServiceReadiness(
            settings: settings,
            credentials: credentials
        )

        XCTAssertFalse(readiness.isReadyForSpeech)

        credentials.savedSlots.insert(.doubaoV3)

        XCTAssertTrue(readiness.isReadyForSpeech)
    }

    func testSettingsStoreTreatsLegacyDoubaoConfigurationAsV1() throws {
        let defaults = makeDefaults()
        let legacy = VoiceServiceConfiguration.doubao(
            appID: "legacy-app-id",
            cluster: "volcano_tts",
            voiceType: "legacy-voice"
        )
        defaults.set(
            try JSONEncoder().encode(legacy),
            forKey: "voice-service-configuration-v1"
        )
        let store = VoiceServiceSettingsStore(defaults: defaults)

        XCTAssertEqual(store.configuration, legacy)
        XCTAssertEqual(store.profiles.activeDoubaoVersion, .v1)
        XCTAssertEqual(store.profiles.doubaoV1, legacy)
    }

    func testSettingsStoreKeepsV1WhenSavingAndSelectingV3() throws {
        let defaults = makeDefaults()
        let store = VoiceServiceSettingsStore(defaults: defaults)
        let v1 = VoiceServiceConfiguration.doubao(
            appID: "v1-app-id",
            cluster: "volcano_tts",
            voiceType: "v1-voice"
        )
        let v3 = VoiceServiceConfiguration.doubaoV3(
            resourceID: "seed-tts-2.0",
            speaker: "v3-speaker"
        )

        try store.save(configuration: v1)
        try store.save(configuration: v3)
        store.selectDoubaoVersion(.v1)

        XCTAssertEqual(store.configuration, v1)
        XCTAssertEqual(store.profiles.doubaoV3, v3)
    }

    func testKeychainUsesLegacyCredentialOnlyForV1() throws {
        let store = KeychainCredentialStore(
            service: "com.xiaofengchen.readless.tests.\(UUID().uuidString)"
        )
        defer {
            try? store.removeCredential(for: .doubaoLegacy)
            try? store.removeCredential(for: .doubaoV1)
            try? store.removeCredential(for: .doubaoV3)
        }

        try store.saveCredential("legacy-test-value", for: .doubaoLegacy)

        XCTAssertEqual(
            try store.credential(for: .doubaoV1),
            "legacy-test-value"
        )
        XCTAssertNil(try store.credential(for: .doubaoV3))

        try store.saveCredential("v1-test-value", for: .doubaoV1)

        XCTAssertEqual(try store.credential(for: .doubaoV1), "v1-test-value")
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "VoiceServiceStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

@MainActor
private final class VoiceServiceConfigurationStoreFake:
    VoiceServiceConfigurationStoring
{
    var configuration: VoiceServiceConfiguration?

    var profiles: VoiceServiceProfiles {
        guard let configuration else {
            return VoiceServiceProfiles()
        }
        return VoiceServiceProfiles.migrated(from: configuration)
    }

    init(configuration: VoiceServiceConfiguration?) {
        self.configuration = configuration
    }

    func selectDoubaoVersion(_ version: DoubaoAPIVersion) {
        guard let configuration else {
            return
        }
        var profiles = VoiceServiceProfiles.migrated(from: configuration)
        profiles.selectDoubaoVersion(version)
        self.configuration = profiles.activeConfiguration
    }
}

@MainActor
private final class VoiceServiceCredentialStoreFake:
    VoiceServiceCredentialChecking
{
    var savedSlots: Set<VoiceCredentialSlot>

    init(savedProviders: Set<VoiceProviderKind> = []) {
        savedSlots = Set(savedProviders.map { provider in
            switch provider {
            case .doubao:
                .doubaoV1
            case .openAICompatible:
                .openAICompatible
            case .openAI, .alibaba:
                .doubaoLegacy
            }
        })
    }

    init(savedSlots: Set<VoiceCredentialSlot>) {
        self.savedSlots = savedSlots
    }

    func hasCredential(for slot: VoiceCredentialSlot) -> Bool {
        savedSlots.contains(slot)
    }
}
