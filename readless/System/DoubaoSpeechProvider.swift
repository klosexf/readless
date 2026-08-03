import Foundation

@MainActor
final class DoubaoSpeechProvider: CloudAudioProviding {
    private let settings: VoiceServiceConfigurationStoring
    private let credentials: VoiceServiceCredentialStoring
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var audioData = Data()
    private var completion: ((Result<Data, ReadingError>) -> Void)?

    init(
        settings: VoiceServiceConfigurationStoring,
        credentials: VoiceServiceCredentialStoring,
        session: URLSession = .shared
    ) {
        self.settings = settings
        self.credentials = credentials
        self.session = session
    }

    func synthesize(
        text: String,
        rate: Float,
        completion: @escaping (Result<Data, ReadingError>) -> Void
    ) {
        guard let configuration = settings.configuration,
              case let .doubao(appID, cluster, voiceType) = configuration,
              let token = try? credentials.credential(for: .doubaoV1),
              !token.isEmpty
        else {
            completion(.failure(.voiceServiceNotConfigured))
            return
        }

        var request = URLRequest(
            url: URL(string: "wss://openspeech.bytedance.com/api/v1/tts/ws_binary")!
        )
        request.timeoutInterval = 15
        request.setValue("Bearer; \(token)", forHTTPHeaderField: "Authorization")

        audioData = Data()
        self.completion = completion
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()

        do {
            let requestData = try JSONSerialization.data(
                withJSONObject: [
                    "app": [
                        "appid": appID,
                        "token": token,
                        "cluster": cluster
                    ],
                    "user": ["uid": "readless-macos"],
                    "audio": [
                        "voice_type": voiceType,
                        "encoding": "mp3",
                        "speed_ratio": min(max(rate, 0.1), 2.0)
                    ],
                    "request": [
                        "reqid": UUID().uuidString,
                        "text": text,
                        "operation": "submit"
                    ]
                ]
            )
            task.send(.data(makePacket(payload: requestData))) { [weak self] error in
                if let error {
                    Task { @MainActor [weak self] in
                        self?.finish(
                            .failure(
                                (error as? URLError)?.code == .timedOut
                                    ? .voiceServiceTimedOut
                                    : .voiceServiceNetworkUnavailable
                            )
                        )
                    }
                    return
                }
                Task { @MainActor [weak self] in
                    self?.receiveNext()
                }
            }
        } catch {
            finish(.failure(.voiceServiceResponseInvalid))
        }
    }

    func cancel() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        completion = nil
        audioData = Data()
    }

    private func receiveNext() {
        task?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case let .success(.data(data)):
                    self.handle(packet: data)
                case .success:
                    self.finish(.failure(.voiceServiceResponseInvalid))
                case let .failure(error):
                    self.finish(
                        .failure(
                            (error as? URLError)?.code == .timedOut
                                ? .voiceServiceTimedOut
                                : .voiceServiceNetworkUnavailable
                        )
                    )
                }
            }
        }
    }

    private func handle(packet: Data) {
        guard packet.count >= 4 else {
            finish(.failure(.voiceServiceResponseInvalid))
            return
        }

        let messageType = packet[1] >> 4
        let flags = packet[1] & 0x0F
        if messageType == 0x0B {
            var offset = 4
            var sequence: Int32?
            if flags != 0 {
                sequence = packet.signedInt32(at: offset)
                offset += 4
            }
            guard let length = packet.uint32(at: offset) else {
                finish(.failure(.voiceServiceResponseInvalid))
                return
            }
            offset += 4
            let end = offset + Int(length)
            guard end <= packet.count else {
                finish(.failure(.voiceServiceResponseInvalid))
                return
            }
            audioData.append(packet[offset..<end])
            if sequence ?? 1 < 0 || flags == 2 || flags == 3 {
                finish(.success(audioData))
            } else {
                receiveNext()
            }
            return
        }

        if messageType == 0x0F {
            let message = String(data: packet.dropFirst(4), encoding: .utf8) ?? ""
            finish(.failure(CloudSpeechErrorMapper.mapDoubaoMessage(message)))
            return
        }

        receiveNext()
    }

    private func finish(_ result: Result<Data, ReadingError>) {
        let completion = completion
        self.completion = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        completion?(result)
    }

    private func makePacket(payload: Data) -> Data {
        var packet = Data([0x11, 0x10, 0x10, 0x00])
        packet.appendUInt32(UInt32(payload.count))
        packet.append(payload)
        return packet
    }
}

private extension Data {
    func uint32(at offset: Int) -> UInt32? {
        guard offset + 4 <= count else { return nil }
        return self[offset..<offset + 4].reduce(0) {
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
