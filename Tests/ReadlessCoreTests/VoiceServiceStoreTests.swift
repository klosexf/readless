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

        credentials.savedProviders.insert(.doubao)

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
}

@MainActor
private final class VoiceServiceConfigurationStoreFake:
    VoiceServiceConfigurationStoring
{
    var configuration: VoiceServiceConfiguration?

    init(configuration: VoiceServiceConfiguration?) {
        self.configuration = configuration
    }
}

@MainActor
private final class VoiceServiceCredentialStoreFake:
    VoiceServiceCredentialChecking
{
    var savedProviders: Set<VoiceProviderKind>

    init(savedProviders: Set<VoiceProviderKind>) {
        self.savedProviders = savedProviders
    }

    func hasCredential(for provider: VoiceProviderKind) -> Bool {
        savedProviders.contains(provider)
    }
}
