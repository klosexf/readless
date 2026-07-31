import AVFoundation

@MainActor
final class SystemSpeechEngine: NSObject, SpeechEngine {
    var onStarted: (() -> Void)?
    var onCompleted: (() -> Void)?
    var onFailed: ((ReadingError) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var ignoresNextCancellation = false
    private var rateMultiplier: Float = 1

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) throws {
        guard !text.isEmpty else {
            throw ReadingError.speechUnavailable
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = min(
            AVSpeechUtteranceMaximumSpeechRate,
            max(
                AVSpeechUtteranceMinimumSpeechRate,
                AVSpeechUtteranceDefaultSpeechRate * rateMultiplier
            )
        )
        synthesizer.speak(utterance)
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .immediate)
    }

    func resume() {
        synthesizer.continueSpeaking()
    }

    func stop() {
        if synthesizer.isSpeaking {
            ignoresNextCancellation = true
        }
        synthesizer.stopSpeaking(at: .immediate)
    }

    func setRate(_ rate: Float) {
        rateMultiplier = rate
    }
}

extension SystemSpeechEngine: @preconcurrency AVSpeechSynthesizerDelegate {
    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        onStarted?()
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        onCompleted?()
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        if ignoresNextCancellation {
            ignoresNextCancellation = false
            return
        }
        onFailed?(.speechFailed)
    }
}
