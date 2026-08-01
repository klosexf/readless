import AVFoundation

@MainActor
final class CloudSpeechEngine: NSObject, SpeechEngine {
    var onStarted: ((SpeechSessionID) -> Void)?
    var onCompleted: ((SpeechSessionID) -> Void)?
    var onFailed: ((SpeechSessionID, ReadingError) -> Void)?
    var onProgress: ((SpeechSessionID, Double) -> Void)?

    private let settings: VoiceServiceConfigurationStoring
    private let credentials: VoiceServiceCredentialStoring
    private var provider: CloudAudioProviding?
    private var player: AVAudioPlayer?
    private var progressTimer: Timer?
    private var activeSessionID: SpeechSessionID?
    private var rate: Float = 1

    init(
        settings: VoiceServiceConfigurationStoring,
        credentials: VoiceServiceCredentialStoring
    ) {
        self.settings = settings
        self.credentials = credentials
    }

    func speak(_ text: String, sessionID: SpeechSessionID) throws {
        guard !text.isEmpty else {
            throw ReadingError.speechUnavailable
        }
        stop()
        guard let configuration = settings.configuration else {
            throw ReadingError.voiceServiceNotConfigured
        }

        let provider: CloudAudioProviding
        switch configuration.provider {
        case .doubao:
            provider = DoubaoSpeechProvider(
                settings: settings,
                credentials: credentials
            )
        case .openAICompatible:
            provider = OpenAICompatibleSpeechProvider(
                settings: settings,
                credentials: credentials
            )
        case .openAI, .alibaba:
            throw ReadingError.voiceServiceNotConfigured
        }
        activeSessionID = sessionID
        self.provider = provider
        provider.synthesize(text: text, rate: rate) { [weak self] result in
            self?.handle(result, sessionID: sessionID)
        }
    }

    func pause() {
        player?.pause()
        progressTimer?.invalidate()
    }

    func resume() {
        guard player?.play() == true else { return }
        installProgressTimer()
    }

    func stop() {
        provider?.cancel()
        provider = nil
        player?.stop()
        player = nil
        progressTimer?.invalidate()
        progressTimer = nil
        activeSessionID = nil
    }

    func seek(to progress: Double) {
        guard let player, player.duration > 0 else { return }
        player.currentTime = player.duration * min(max(progress, 0), 1)
        onProgress?(activeSessionID ?? 0, player.currentTime / player.duration)
    }

    func setRate(_ rate: Float) {
        self.rate = rate
        player?.enableRate = true
        player?.rate = rate
    }

    private func handle(
        _ result: Result<Data, ReadingError>,
        sessionID: SpeechSessionID
    ) {
        guard sessionID == activeSessionID else { return }
        switch result {
        case let .success(data):
            do {
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                player.enableRate = true
                player.rate = rate
                self.player = player
                guard player.play() else {
                    throw ReadingError.voiceServiceResponseInvalid
                }
                onStarted?(sessionID)
                installProgressTimer()
            } catch let error as ReadingError {
                fail(error, sessionID: sessionID)
            } catch {
                fail(.voiceServiceResponseInvalid, sessionID: sessionID)
            }
        case let .failure(error):
            fail(error, sessionID: sessionID)
        }
    }

    private func fail(_ error: ReadingError, sessionID: SpeechSessionID) {
        guard activeSessionID == sessionID else { return }
        progressTimer?.invalidate()
        progressTimer = nil
        player = nil
        provider = nil
        activeSessionID = nil
        onFailed?(sessionID, error)
    }

    private func installProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(
            withTimeInterval: 0.1,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let player = self.player,
                      let sessionID = self.activeSessionID,
                      player.duration > 0
                else {
                    return
                }
                self.onProgress?(
                    sessionID,
                    player.currentTime / player.duration
                )
            }
        }
    }
}

extension CloudSpeechEngine: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        guard let sessionID = activeSessionID else { return }
        progressTimer?.invalidate()
        progressTimer = nil
        self.player = nil
        provider = nil
        activeSessionID = nil
        if flag {
            onCompleted?(sessionID)
        } else {
            onFailed?(sessionID, .voiceServiceResponseInvalid)
        }
    }
}
