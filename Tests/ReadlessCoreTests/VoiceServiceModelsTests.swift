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

    func testOpenAIAndAlibabaRemainUnavailableCatalogEntries() {
        XCTAssertTrue(VoiceProviderKind.doubao.isAvailable)
        XCTAssertTrue(VoiceProviderKind.openAICompatible.isAvailable)
        XCTAssertFalse(VoiceProviderKind.openAI.isAvailable)
        XCTAssertFalse(VoiceProviderKind.alibaba.isAvailable)
    }
}
