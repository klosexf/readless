import Foundation

enum CloudSpeechRequestError: Error {
    case incompatibleConfiguration
    case invalidRequestBody
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
        if normalized.contains("auth") || normalized.contains("grant") {
            return .voiceServiceCredentialInvalid
        }
        if normalized.contains("timeout") {
            return .voiceServiceTimedOut
        }
        return .voiceServiceResponseInvalid
    }
}
