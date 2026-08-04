import Foundation

@MainActor
final class DoubaoV3SpeechProvider: CloudAudioProviding {
    private let settings: VoiceServiceConfigurationStoring
    private let credentials: VoiceServiceCredentialStoring
    private let session: URLSession
    private var task: URLSessionDataTask?
    private var requestGeneration = 0

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
              )
        else {
            completion(.failure(.voiceServiceNotConfigured))
            return
        }

        task?.cancel()
        requestGeneration += 1
        let generation = requestGeneration
        let task = session.dataTask(with: request) {
            [weak self] data, response, transportError in
            Task { @MainActor [weak self] in
                guard let self,
                      self.requestGeneration == generation else {
                    return
                }
                self.task = nil

                if let error = transportError as? URLError {
                    completion(
                        .failure(
                            error.code == .timedOut
                                ? .voiceServiceTimedOut
                                : .voiceServiceNetworkUnavailable
                        )
                    )
                    return
                }
                if transportError != nil {
                    completion(.failure(.voiceServiceNetworkUnavailable))
                    return
                }
                guard let response = response as? HTTPURLResponse else {
                    completion(.failure(.voiceServiceNetworkUnavailable))
                    return
                }
                guard (200...299).contains(response.statusCode) else {
                    completion(
                        .failure(
                            self.mapHTTPFailure(
                                statusCode: response.statusCode,
                                data: data
                            )
                        )
                    )
                    return
                }
                guard let data, !data.isEmpty else {
                    completion(.failure(.voiceServiceResponseInvalid))
                    return
                }
                completion(DoubaoV3HTTPResponseDecoder.decode(data))
            }
        }
        self.task = task
        task.resume()
    }

    func cancel() {
        requestGeneration += 1
        task?.cancel()
        task = nil
    }

    private func mapHTTPFailure(
        statusCode: Int,
        data: Data?
    ) -> ReadingError {
        if [401, 403, 408, 429, 504].contains(statusCode) {
            return CloudSpeechErrorMapper.map(statusCode: statusCode)
        }
        if let data,
           case let .failure(serviceError) =
               DoubaoV3HTTPResponseDecoder.decode(data),
           serviceError != .voiceServiceResponseInvalid {
            return serviceError
        }
        return CloudSpeechErrorMapper.map(statusCode: statusCode)
    }
}
