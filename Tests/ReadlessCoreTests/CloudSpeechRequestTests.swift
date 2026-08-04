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

    func testDoubaoV3RequestUsesHTTPHeadersAndJSONBody() throws {
        let requestID = try XCTUnwrap(
            UUID(uuidString: "11111111-2222-3333-4444-555555555555")
        )
        let request = try DoubaoV3RequestBuilder.make(
            configuration: .doubaoV3(
                resourceID: "seed-tts-2.0",
                speaker: "test-speaker"
            ),
            apiKey: "unit-test-key",
            text: "测试",
            rate: 1,
            requestID: requestID
        )

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://openspeech.bytedance.com/api/v3/tts/unidirectional"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Api-Key"),
            "unit-test-key"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Api-Resource-Id"),
            "seed-tts-2.0"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Api-Request-Id"),
            requestID.uuidString
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )

        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: XCTUnwrap(request.httpBody)
            ) as? [String: Any]
        )
        let parameters = try XCTUnwrap(body["req_params"] as? [String: Any])
        let audio = try XCTUnwrap(parameters["audio_params"] as? [String: Any])

        XCTAssertEqual(parameters["text"] as? String, "测试")
        XCTAssertEqual(parameters["speaker"] as? String, "test-speaker")
        XCTAssertEqual(audio["format"] as? String, "mp3")
        XCTAssertEqual(audio["sample_rate"] as? Int, 24_000)
        XCTAssertEqual(audio["speech_rate"] as? Int, 0)
    }

    func testDoubaoV3HTTPResponseMergesAudioChunks() {
        let response = Data(
            """
            {"code":0,"data":"AQI="}
            {"code":0,"data":"AwQ="}
            {"code":20000000,"message":"OK"}
            """.utf8
        )
        XCTAssertEqual(
            DoubaoV3HTTPResponseDecoder.decode(response),
            .success(Data([0x01, 0x02, 0x03, 0x04]))
        )
    }

    func testDoubaoV3HTTPResponseRejectsInvalidBase64() {
        let response = Data(#"{"code":0,"data":"%%%"}"#.utf8)

        XCTAssertEqual(
            DoubaoV3HTTPResponseDecoder.decode(response),
            .failure(.voiceServiceResponseInvalid)
        )
    }

    func testDoubaoV3HTTPResponseMapsCredentialMessage() {
        let response = Data(
            #"{"code":45000000,"message":"invalid api key"}"#.utf8
        )

        XCTAssertEqual(
            DoubaoV3HTTPResponseDecoder.decode(response),
            .failure(.voiceServiceCredentialInvalid)
        )
    }

    func testDoubaoV3HTTPResponseRejectsEmptyAudio() {
        let response = Data(
            #"{"code":20000000,"message":"OK"}"#.utf8
        )

        XCTAssertEqual(
            DoubaoV3HTTPResponseDecoder.decode(response),
            .failure(.voiceServiceResponseInvalid)
        )
    }

    func testV3ConfigurationRoutesOnlyToV3Transport() {
        let configuration = VoiceServiceConfiguration.doubaoV3(
            resourceID: "seed-tts-2.0",
            speaker: "test-speaker"
        )

        XCTAssertEqual(
            CloudSpeechTransport.route(for: configuration),
            .doubaoV3
        )
    }
}
