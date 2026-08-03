import Foundation

@MainActor
final class DoubaoV3SpeechProvider: CloudAudioProviding {
    private let settings: VoiceServiceConfigurationStoring
    private let credentials: VoiceServiceCredentialStoring
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var collector = DoubaoV3SynthesisCollector()
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
              case .doubaoV3 = configuration,
              let apiKey = try? credentials.credential(for: .doubaoV3),
              !apiKey.isEmpty,
              let request = try? DoubaoV3RequestBuilder.make(
                  configuration: configuration,
                  apiKey: apiKey,
                  text: text,
                  rate: rate
              ),
              let packet = request.httpBody
        else {
            completion(.failure(.voiceServiceNotConfigured))
            return
        }

        collector = DoubaoV3SynthesisCollector()
        self.completion = completion
        var handshakeRequest = request
        handshakeRequest.httpBody = nil
        let task = session.webSocketTask(with: handshakeRequest)
        self.task = task
        task.resume()
        task.send(.data(packet)) { [weak self] error in
            if let error {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.finish(.failure(self.mapTransportError(error)))
                }
                return
            }
            Task { @MainActor [weak self] in
                self?.receiveNext()
            }
        }
    }

    func cancel() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        completion = nil
        collector = DoubaoV3SynthesisCollector()
    }

    private func receiveNext() {
        guard completion != nil else { return }
        task?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case let .success(.data(packet)):
                    self.handle(packet)
                case .success:
                    self.finish(.failure(.voiceServiceResponseInvalid))
                case let .failure(error):
                    self.finish(.failure(self.mapTransportError(error)))
                }
            }
        }
    }

    private func handle(_ packet: Data) {
        if let result = collector.consume(DoubaoV3PacketDecoder.decode(packet)) {
            finish(result)
        } else {
            receiveNext()
        }
    }

    private func mapTransportError(_ error: Error) -> ReadingError {
        (error as? URLError)?.code == .timedOut
            ? .voiceServiceTimedOut
            : .voiceServiceNetworkUnavailable
    }

    private func finish(_ result: Result<Data, ReadingError>) {
        let completion = completion
        self.completion = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        completion?(result)
    }
}
