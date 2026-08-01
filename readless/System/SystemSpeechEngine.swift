import AVFoundation

@MainActor
final class SystemSpeechEngine: NSObject, SpeechEngine {
    var onStarted: ((SpeechSessionID) -> Void)?
    var onCompleted: ((SpeechSessionID) -> Void)?
    var onFailed: ((SpeechSessionID, ReadingError) -> Void)?
    var onProgress: ((SpeechSessionID, Double) -> Void)?

    private let worker: SpeechSynthesizerWorker

    override init() {
        worker = SpeechSynthesizerWorker()
        super.init()
        worker.onStarted = { [weak self] sessionID in
            Task { @MainActor [weak self] in
                self?.onStarted?(sessionID)
            }
        }
        worker.onCompleted = { [weak self] sessionID in
            Task { @MainActor [weak self] in
                self?.onCompleted?(sessionID)
            }
        }
        worker.onFailed = { [weak self] sessionID, error in
            Task { @MainActor [weak self] in
                self?.onFailed?(sessionID, error)
            }
        }
        worker.onProgress = { [weak self] sessionID, progress in
            Task { @MainActor [weak self] in
                self?.onProgress?(sessionID, progress)
            }
        }
    }

    func speak(_ text: String, sessionID: SpeechSessionID) throws {
        guard !text.isEmpty else {
            throw ReadingError.speechUnavailable
        }
        worker.speak(text, sessionID: sessionID)
    }

    func pause() {
        worker.pause()
    }

    func resume() {
        worker.resume()
    }

    func stop() {
        worker.stop()
    }

    func seek(to progress: Double) {
        worker.seek(to: progress)
    }

    func setRate(_ rate: Float) {
        worker.setRate(rate)
    }
}

private final class SpeechSynthesizerWorker: NSObject {
    var onStarted: ((SpeechSessionID) -> Void)?
    var onCompleted: ((SpeechSessionID) -> Void)?
    var onFailed: ((SpeechSessionID, ReadingError) -> Void)?
    var onProgress: ((SpeechSessionID, Double) -> Void)?

    private let queue = DispatchQueue(
        label: "com.xiaofengchen.readless.speech",
        qos: .default
    )
    private var synthesizer: AVSpeechSynthesizer?
    private var rateMultiplier: Float = 1
    private var fullText: NSString?
    private var spokenOffset = 0
    private var activeUtterance: AVSpeechUtterance?
    private var initialUtterance: AVSpeechUtterance?
    private var activeSessionID: SpeechSessionID?
    private var initialSessionID: SpeechSessionID?

    func speak(_ text: String, sessionID: SpeechSessionID) {
        queue.async { [weak self] in
            guard let self else { return }
            self.fullText = text as NSString
            self.spokenOffset = 0
            self.onProgress?(sessionID, 0)
            self.enqueueUtterance(
                startingAt: 0,
                reportsStart: true,
                sessionID: sessionID
            )
        }
    }

    func pause() {
        queue.async { [weak self] in
            self?.synthesizer?.pauseSpeaking(at: .immediate)
        }
    }

    func resume() {
        queue.async { [weak self] in
            self?.synthesizer?.continueSpeaking()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.clearPlayback()
            self.synthesizer?.stopSpeaking(at: .immediate)
        }
    }

    func seek(to progress: Double) {
        queue.async { [weak self] in
            guard
                let self,
                let fullText = self.fullText,
                let sessionID = self.activeSessionID
            else { return }

            let clampedProgress = min(max(progress, 0), 1)
            if clampedProgress == 1 {
                self.clearPlayback()
                self.synthesizer?.stopSpeaking(at: .immediate)
                self.onProgress?(sessionID, 1)
                self.onCompleted?(sessionID)
                return
            }

            let targetOffset = self.composedCharacterStart(
                near: Int(
                    (Double(fullText.length) * clampedProgress).rounded(.down)
                ),
                in: fullText
            )
            self.activeUtterance = nil
            self.initialUtterance = nil
            self.synthesizer?.stopSpeaking(at: .immediate)
            self.enqueueUtterance(
                startingAt: targetOffset,
                reportsStart: false,
                sessionID: sessionID
            )
        }
    }

    func setRate(_ rate: Float) {
        queue.async { [weak self] in
            self?.rateMultiplier = rate
        }
    }

    private func enqueueUtterance(
        startingAt offset: Int,
        reportsStart: Bool,
        sessionID: SpeechSessionID
    ) {
        guard let fullText, offset < fullText.length else {
            onCompleted?(sessionID)
            return
        }

        let synthesizer = self.synthesizer ?? {
            let synthesizer = AVSpeechSynthesizer()
            synthesizer.delegate = self
            self.synthesizer = synthesizer
            return synthesizer
        }()
        spokenOffset = offset
        let utterance = AVSpeechUtterance(
            string: fullText.substring(from: offset)
        )
        utterance.rate = min(
            AVSpeechUtteranceMaximumSpeechRate,
            max(
                AVSpeechUtteranceMinimumSpeechRate,
                AVSpeechUtteranceDefaultSpeechRate * rateMultiplier
            )
        )
        activeUtterance = utterance
        activeSessionID = sessionID
        if reportsStart {
            initialUtterance = utterance
            initialSessionID = sessionID
        }
        synthesizer.speak(utterance)
    }

    private func clearPlayback() {
        activeUtterance = nil
        initialUtterance = nil
        activeSessionID = nil
        initialSessionID = nil
        fullText = nil
    }

    private func markPlaybackCompleted() {
        activeUtterance = nil
        initialUtterance = nil
        initialSessionID = nil
    }

    private func composedCharacterStart(
        near offset: Int,
        in text: NSString
    ) -> Int {
        guard text.length > 0 else { return 0 }
        let safeOffset = min(max(offset, 0), text.length - 1)
        return text.rangeOfComposedCharacterSequence(at: safeOffset).location
    }
}

extension SpeechSynthesizerWorker: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        queue.async { [weak self] in
            guard
                let self,
                utterance === self.initialUtterance,
                let sessionID = self.initialSessionID
            else { return }
            self.onStarted?(sessionID)
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        queue.async { [weak self] in
            guard
                let self,
                utterance === self.activeUtterance,
                let sessionID = self.activeSessionID
            else { return }
            self.markPlaybackCompleted()
            self.onCompleted?(sessionID)
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        queue.async { [weak self] in
            guard
                let self,
                utterance === self.activeUtterance,
                let sessionID = self.activeSessionID
            else { return }
            self.clearPlayback()
            self.onFailed?(sessionID, .speechFailed)
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        queue.async { [weak self] in
            guard
                let self,
                utterance === self.activeUtterance,
                let fullText = self.fullText,
                let sessionID = self.activeSessionID,
                fullText.length > 0
            else {
                return
            }
            let spokenLength = self.spokenOffset
                + characterRange.location
                + characterRange.length
            self.onProgress?(
                sessionID,
                min(max(Double(spokenLength) / Double(fullText.length), 0), 1)
            )
        }
    }
}
