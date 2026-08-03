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
        string: "wss://openspeech.bytedance.com/api/v3/tts/unidirectional/stream"
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
        request.timeoutInterval = 15
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(
            requestID.uuidString,
            forHTTPHeaderField: "X-Api-Request-Id"
        )
        request.httpBody = makeFullClientRequestPacket(payload: payload)
        return request
    }

    private static func makeFullClientRequestPacket(payload: Data) -> Data {
        var packet = Data([0x11, 0x10, 0x10, 0x00])
        packet.appendUInt32(UInt32(payload.count))
        packet.append(payload)
        return packet
    }
}

enum DoubaoV3Response: Equatable {
    case audio(Data)
    case finished
    case failure(ReadingError)
    case ignore
}

struct DoubaoV3SynthesisCollector {
    private var audioData = Data()

    mutating func consume(
        _ response: DoubaoV3Response
    ) -> Result<Data, ReadingError>? {
        switch response {
        case let .audio(data):
            audioData.append(data)
            return nil
        case .finished:
            guard !audioData.isEmpty else {
                return .failure(.voiceServiceResponseInvalid)
            }
            return .success(audioData)
        case let .failure(error):
            return .failure(error)
        case .ignore:
            return nil
        }
    }
}

enum DoubaoV3PacketDecoder {
    private enum MessageType: UInt8 {
        case fullServerResponse = 0x09
        case audioOnlyServer = 0x0B
        case error = 0x0F
    }

    private enum Event: Int32 {
        case connectionStarted = 50
        case connectionFailed = 51
        case connectionFinished = 52
        case sessionFinished = 152
        case sessionFailed = 153
        case ttsResponse = 352
    }

    static func decode(_ packet: Data) -> DoubaoV3Response {
        guard packet.count >= 4 else {
            return .failure(.voiceServiceResponseInvalid)
        }
        let headerSize = Int(packet[0] & 0x0F) * 4
        guard headerSize >= 4, headerSize <= packet.count,
              let messageType = MessageType(rawValue: packet[1] >> 4)
        else {
            return .failure(.voiceServiceResponseInvalid)
        }

        let flags = packet[1] & 0x0F
        var offset = headerSize
        var serverEvent: Event?
        var errorCode: UInt32?

        if messageType == .error {
            guard let code = packet.uint32(at: offset) else {
                return .failure(.voiceServiceResponseInvalid)
            }
            errorCode = code
            offset += 4
        } else if flags == 0x01 || flags == 0x03 {
            guard packet.signedInt32(at: offset) != nil else {
                return .failure(.voiceServiceResponseInvalid)
            }
            offset += 4
        }

        if flags == 0x04 {
            guard let rawEvent = packet.signedInt32(at: offset) else {
                return .failure(.voiceServiceResponseInvalid)
            }
            serverEvent = Event(rawValue: rawEvent)
            offset += 4

            if serverEvent != .connectionStarted,
               serverEvent != .connectionFailed,
               serverEvent != .connectionFinished {
                guard let sessionIDLength = packet.uint32(at: offset) else {
                    return .failure(.voiceServiceResponseInvalid)
                }
                offset += 4
                let sessionIDEnd = offset + Int(sessionIDLength)
                guard sessionIDEnd <= packet.count else {
                    return .failure(.voiceServiceResponseInvalid)
                }
                offset = sessionIDEnd
            }
        }

        guard let payloadLength = packet.uint32(at: offset) else {
            return .failure(.voiceServiceResponseInvalid)
        }
        offset += 4
        let payloadEnd = offset + Int(payloadLength)
        guard payloadEnd <= packet.count else {
            return .failure(.voiceServiceResponseInvalid)
        }
        let payload = Data(packet[offset..<payloadEnd])

        switch messageType {
        case .audioOnlyServer:
            guard serverEvent == nil || serverEvent == .ttsResponse else {
                return .ignore
            }
            return .audio(payload)
        case .fullServerResponse:
            switch serverEvent {
            case .sessionFinished:
                return .finished
            case .sessionFailed:
                return .failure(mapFailurePayload(payload))
            default:
                return .ignore
            }
        case .error:
            return .failure(
                CloudSpeechErrorMapper.mapDoubaoV3Error(
                    protocolCode: errorCode,
                    payload: payload
                )
            )
        }
    }

    private static func mapFailurePayload(_ payload: Data) -> ReadingError {
        let message = String(data: payload, encoding: .utf8) ?? ""
        return CloudSpeechErrorMapper.mapDoubaoMessage(message)
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

private extension Data {
    func uint32(at offset: Int) -> UInt32? {
        guard offset + 4 <= count else { return nil }
        return self[offset..<(offset + 4)].reduce(0) {
            ($0 << 8) | UInt32($1)
        }
    }

    func signedInt32(at offset: Int) -> Int32? {
        uint32(at: offset).map { Int32(bitPattern: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(contentsOf: [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ])
    }
}
