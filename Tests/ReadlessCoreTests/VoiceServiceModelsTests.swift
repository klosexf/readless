import XCTest
@testable import ReadlessCore

final class VoiceServiceModelsTests: XCTestCase {
    func testDoubaoRequiresAppIDBeforeOtherFields() {
        let configuration = VoiceServiceConfiguration.doubao(
            appID: "",
            cluster: "",
            voiceType: ""
        )

        XCTAssertEqual(configuration.validationError, .appIDRequired)
    }

    func testCompatibleServiceRequiresSecureBaseURL() {
        let configuration = VoiceServiceConfiguration.openAICompatible(
            baseURL: "http://tts.example",
            model: "",
            voice: ""
        )

        XCTAssertEqual(
            configuration.validationError,
            .secureBaseURLRequired
        )
    }

    func testDoubaoV3RequiresResourceIDBeforeSpeaker() {
        let configuration = VoiceServiceConfiguration.doubaoV3(
            resourceID: "",
            speaker: ""
        )

        XCTAssertEqual(configuration.validationError, .resourceIDRequired)
    }

    func testDoubaoVersionsUseSeparateCredentialSlots() {
        let v1 = VoiceServiceConfiguration.doubao(
            appID: "app-id",
            cluster: "volcano_tts",
            voiceType: "voice"
        )
        let v3 = VoiceServiceConfiguration.doubaoV3(
            resourceID: "seed-tts-2.0",
            speaker: "voice"
        )

        XCTAssertEqual(v1.credentialSlot, .doubaoV1)
        XCTAssertEqual(v3.credentialSlot, .doubaoV3)
    }

    func testOpenAIAndAlibabaRemainUnavailableCatalogEntries() {
        XCTAssertTrue(VoiceProviderKind.doubao.isAvailable)
        XCTAssertTrue(VoiceProviderKind.openAICompatible.isAvailable)
        XCTAssertFalse(VoiceProviderKind.openAI.isAvailable)
        XCTAssertFalse(VoiceProviderKind.alibaba.isAvailable)
    }

    func testUnavailableProviderCannotBeSaved() {
        let error = VoiceServiceConfigurationValidator.saveError(
            for: .openAI,
            configuration: .openAICompatible(
                baseURL: "https://tts.example",
                model: "tts-1",
                voice: "nova"
            ),
            credential: "test-api-key"
        )

        XCTAssertEqual(error, .validation(.unavailable))
    }
}
