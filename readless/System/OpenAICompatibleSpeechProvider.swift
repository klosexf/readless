import Foundation

@MainActor
protocol CloudAudioProviding: AnyObject {
    func synthesize(
        text: String,
        rate: Float,
        completion: @escaping (Result<Data, ReadingError>) -> Void
    )
    func cancel()
}

@MainActor
final class OpenAICompatibleSpeechProvider: CloudAudioProviding {
    private let settings: VoiceServiceConfigurationStoring
    private let credentials: VoiceServiceCredentialStoring
    private let session: URLSession
    private var task: URLSessionDataTask?

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
              configuration.provider == .openAICompatible,
              let apiKey = try? credentials.credential(
                  for: .openAICompatible
              ),
              !apiKey.isEmpty,
              let request = try? OpenAICompatibleRequestBuilder.make(
                  configuration: configuration,
                  apiKey: apiKey,
                  text: text
              )
        else {
            completion(.failure(.voiceServiceNotConfigured))
            return
        }

        task = session.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.task = nil
                if let error = error as? URLError {
                    completion(
                        .failure(
                            error.code == .timedOut
                                ? .voiceServiceTimedOut
                                : .voiceServiceNetworkUnavailable
                        )
                    )
                    return
                }
                guard let response = response as? HTTPURLResponse else {
                    completion(.failure(.voiceServiceNetworkUnavailable))
                    return
                }
                guard (200...299).contains(response.statusCode) else {
                    completion(
                        .failure(
                            CloudSpeechErrorMapper.map(
                                statusCode: response.statusCode
                            )
                        )
                    )
                    return
                }
                guard let data, !data.isEmpty else {
                    completion(.failure(.voiceServiceResponseInvalid))
                    return
                }
                completion(.success(data))
            }
        }
        task?.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
