import XCTest
@testable import ReadlessCore

final class CloudSpeechRequestTests: XCTestCase {
    func testCompatibleRequestUsesSpeechPathAndAuthorization() throws {
        let request = try OpenAICompatibleRequestBuilder.make(
            configuration: .openAICompatible(
                baseURL: "https://tts.example/v1",
                model: "tts-model",
                voice: "nova"
            ),
            apiKey: "test-api-key",
            text: "测试"
        )

        XCTAssertEqual(request.url?.path, "/v1/audio/speech")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer test-api-key"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
    }

    func testUnauthorizedResponseMapsToCredentialError() {
        XCTAssertEqual(
            CloudSpeechErrorMapper.map(statusCode: 401),
            .voiceServiceCredentialInvalid
        )
    }
}
