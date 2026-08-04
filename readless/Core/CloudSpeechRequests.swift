import Foundation

enum CloudSpeechRequestError: Error {
    case incompatibleConfiguration
    case invalidRequestBody
}

enum CloudSpeechTransport: Equatable {
    case doubaoV1
    case doubaoV3
    case openAICompatible

    static func route(
        for configuration: VoiceServiceConfiguration
    ) -> CloudSpeechTransport {
        switch configuration {
        case .doubao:
            .doubaoV1
        case .doubaoV3:
            .doubaoV3
        case .openAICompatible:
            .openAICompatible
        }
    }
}

enum DoubaoV3RequestBuilder {
    private static let endpoint = URL(
        string: "https://openspeech.bytedance.com/api/v3/tts/unidirectional"
    )!

    static func make(
        configuration: VoiceServiceConfiguration,
        apiKey: String,
        text: String,
        rate: Float,
        requestID: UUID = UUID()
    ) throws -> URLRequest {
        guard case let .doubaoV3(resourceID, speaker) = configuration,
              configuration.validationError == nil,
              !apiKey.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty
        else {
            throw CloudSpeechRequestError.incompatibleConfiguration
        }

        let speechRate = Int(
            ((min(max(rate, 0.5), 2) - 1) * 100).rounded()
        )
        let payload = try JSONSerialization.data(
            withJSONObject: [
                "req_params": [
                    "text": text,
                    "speaker": speaker,
                    "audio_params": [
                        "format": "mp3",
                        "sample_rate": 24_000,
                        "speech_rate": speechRate
                    ]
                ]
            ]
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(
            requestID.uuidString,
            forHTTPHeaderField: "X-Api-Request-Id"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = payload
        return request
    }
}

enum DoubaoV3HTTPResponseDecoder {
    private struct Chunk: Decodable {
        let code: Int
        let data: String?
    }

    static func decode(_ response: Data) -> Result<Data, ReadingError> {
        guard let body = String(data: response, encoding: .utf8) else {
            return .failure(.voiceServiceResponseInvalid)
        }

        let lines = body.split(whereSeparator: { $0.isNewline })
        guard !lines.isEmpty else {
            return .failure(.voiceServiceResponseInvalid)
        }

        var audio = Data()
        for line in lines {
            let lineData = Data(line.utf8)
            guard let chunk = try? JSONDecoder().decode(
                Chunk.self,
                from: lineData
            ) else {
                return .failure(.voiceServiceResponseInvalid)
            }

            guard chunk.code == 0 || chunk.code == 20_000_000 else {
                return .failure(
                    CloudSpeechErrorMapper.mapDoubaoV3Error(
                        protocolCode: UInt32(exactly: chunk.code),
                        payload: lineData
                    )
                )
            }

            if let encodedAudio = chunk.data, !encodedAudio.isEmpty {
                guard let chunkAudio = Data(
                    base64Encoded: encodedAudio
                ), !chunkAudio.isEmpty else {
                    return .failure(.voiceServiceResponseInvalid)
                }
                audio.append(chunkAudio)
            }
        }

        guard !audio.isEmpty else {
            return .failure(.voiceServiceResponseInvalid)
        }
        return .success(audio)
    }
}

enum OpenAICompatibleRequestBuilder {
    static func make(
        configuration: VoiceServiceConfiguration,
        apiKey: String,
        text: String
    ) throws -> URLRequest {
        guard case let .openAICompatible(baseURL, model, voice) = configuration,
              configuration.validationError == nil,
              var endpoint = URL(string: baseURL)
        else {
            throw CloudSpeechRequestError.incompatibleConfiguration
        }

        if endpoint.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) != "v1" {
            endpoint.appendPathComponent("v1")
        }
        endpoint.appendPathComponent("audio")
        endpoint.appendPathComponent("speech")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                model: model,
                input: text,
                voice: voice,
                responseFormat: "mp3"
            )
        )
        return request
    }

    private struct RequestBody: Encodable {
        let model: String
        let input: String
        let voice: String
        let responseFormat: String

        enum CodingKeys: String, CodingKey {
            case model
            case input
            case voice
            case responseFormat = "response_format"
        }
    }
}

enum CloudSpeechErrorMapper {
    static func map(statusCode: Int) -> ReadingError {
        switch statusCode {
        case 401, 403:
            .voiceServiceCredentialInvalid
        case 408, 504:
            .voiceServiceTimedOut
        case 429:
            .voiceServiceQuotaExceeded
        case 500...599:
            .voiceServiceResponseInvalid
        default:
            .voiceServiceResponseInvalid
        }
    }

    static func mapDoubaoMessage(_ message: String) -> ReadingError {
        let normalized = message.lowercased()
        if normalized.contains("quota") || normalized.contains("concurrency") {
            return .voiceServiceQuotaExceeded
        }
        if normalized.contains("auth")
            || normalized.contains("grant")
            || normalized.contains("api key") {
            return .voiceServiceCredentialInvalid
        }
        if normalized.contains("timeout") {
            return .voiceServiceTimedOut
        }
        return .voiceServiceResponseInvalid
    }

    static func mapDoubaoV3Error(
        protocolCode: UInt32?,
        payload: Data
    ) -> ReadingError {
        if let protocolCode,
           let mapped = knownHTTPStatusMapping(for: protocolCode) {
            return mapped
        }
        return mapDoubaoMessage(message(from: payload))
    }

    private static func knownHTTPStatusMapping(
        for code: UInt32
    ) -> ReadingError? {
        switch code {
        case 401, 403:
            .voiceServiceCredentialInvalid
        case 408, 504:
            .voiceServiceTimedOut
        case 429:
            .voiceServiceQuotaExceeded
        default:
            nil
        }
    }

    private static func message(from payload: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: payload),
              let response = object as? [String: Any]
        else {
            return String(data: payload, encoding: .utf8) ?? ""
        }
        return ["message", "err_msg", "error", "error_description"]
            .compactMap { response[$0] as? String }
            .joined(separator: " ")
    }
}
