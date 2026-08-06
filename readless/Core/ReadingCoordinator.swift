import Foundation

@MainActor
final class ReadingCoordinator {
    private let state: ReadlessAppState
    private let permission: AccessibilityPermissionChecking
    private let selectionReader: SelectionReading
    private let clipboardReader: ClipboardReading
    private let voiceServiceReadiness: VoiceServiceReadinessChecking
    private let sanitizer: TextSanitizing
    private let sentenceLocator: SentenceLocating
    private let speech: SpeechEngine
    private let scheduleAfter: (
        TimeInterval,
        @escaping @MainActor () -> Void
    ) -> Void
    private var lastFingerprint: SelectionFingerprint?
    private var completionGeneration = 0
    private var activeSpeechSessionID: SpeechSessionID = 0

    init(
        state: ReadlessAppState,
        permission: AccessibilityPermissionChecking,
        selectionReader: SelectionReading,
        clipboardReader: ClipboardReading,
        voiceServiceReadiness: VoiceServiceReadinessChecking,
        sanitizer: TextSanitizing,
        sentenceLocator: SentenceLocating,
        speech: SpeechEngine,
        scheduleAfter: (
            (
                TimeInterval,
                @escaping @MainActor () -> Void
            ) -> Void
        )? = nil
    ) {
        self.state = state
        self.permission = permission
        self.selectionReader = selectionReader
        self.clipboardReader = clipboardReader
        self.voiceServiceReadiness = voiceServiceReadiness
        self.sanitizer = sanitizer
        self.sentenceLocator = sentenceLocator
        self.speech = speech
        self.scheduleAfter = scheduleAfter ?? { delay, action in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                action()
            }
        }

        speech.onStarted = { [weak self] sessionID in
            self?.didStart(sessionID: sessionID)
        }
        speech.onCompleted = { [weak self] sessionID in
            self?.didComplete(sessionID: sessionID)
        }
        speech.onFailed = { [weak self] sessionID, error in
            self?.fail(error, sessionID: sessionID)
        }
        speech.onProgress = { [weak self] sessionID, progress in
            self?.updateProgress(progress, sessionID: sessionID)
        }
    }

    func handleReadShortcut() {
        guard voiceServiceReadiness.isReadyForSpeech else {
            state.showOnboarding(at: .configuration)
            return
        }

        guard permission.isTrusted else {
            fail(.accessibilityPermissionRequired)
            permission.requestAccessPrompt()
            return
        }

        do {
            let snapshot = try selectionReader.readSelection()
            try handle(snapshot)
        } catch let error as ReadingError {
            if canToggleWhenSelectionIsUnavailable(error) {
                togglePlayback()
            } else {
                fail(error)
            }
        } catch {
            fail(.selectedTextUnsupported)
        }
    }

    func readClipboard() {
        guard voiceServiceReadiness.isReadyForSpeech else {
            state.showOnboarding(at: .configuration)
            return
        }

        guard let text = clipboardReader.readString() else {
            reportClipboardError(.clipboardEmpty)
            return
        }

        do {
            let cleaned = try sanitizer.sanitize(text)
            try start(
                text: cleaned,
                sourceApplication: "剪贴板",
                fingerprint: nil
            )
        } catch let error as ReadingError {
            reportClipboardError(error)
        } catch {
            reportClipboardError(.speechFailed)
        }
    }

    func readTestSpeech() {
        guard voiceServiceReadiness.isReadyForSpeech else {
            state.showOnboarding(at: .configuration)
            return
        }

        do {
            try start(
                text: "你好，这是桌面听读助手的内置测试语音。",
                sourceApplication: "语音服务测试",
                fingerprint: nil
            )
        } catch let error as ReadingError {
            fail(error)
        } catch {
            fail(.speechFailed)
        }
    }

    func togglePlayback() {
        switch state.playbackState {
        case .playing:
            speech.pause()
            state.togglePlayback()
        case .paused:
            speech.resume()
            state.togglePlayback()
        default:
            break
        }
    }

    func setRate(_ rate: Float) {
        speech.setRate(rate)
    }

    func seek(to progress: Double) {
        switch state.playbackState {
        case .playing:
            state.updateProgress(progress)
        case .completed:
            completionGeneration += 1
            state.restartCompletedPlayback(at: progress)
        default:
            return
        }
        speech.seek(to: progress)
    }

    func stop() {
        speech.stop()
        activeSpeechSessionID += 1
        completionGeneration += 1
        lastFingerprint = nil
        state.stopPlayback()
    }

    private func handle(_ snapshot: SelectionSnapshot) throws {
        let cleaned = try sanitizer.sanitize(snapshot.text)
        let fingerprint = SelectionFingerprint(
            sanitizedText: cleaned,
            bundleIdentifier: snapshot.bundleIdentifier,
            selectionIdentifier: snapshot.selectionIdentifier
        )

        if fingerprint == lastFingerprint,
           (
               state.playbackState == .playing
                   || state.playbackState == .paused
           ) {
            togglePlayback()
            return
        }

        try start(
            text: cleaned,
            sourceApplication: snapshot.sourceApplication,
            fingerprint: fingerprint
        )
    }

    private func start(
        text: String,
        sourceApplication: String,
        fingerprint: SelectionFingerprint?
    ) throws {
        if state.playbackState != .idle {
            speech.stop()
        }
        activeSpeechSessionID += 1
        completionGeneration += 1
        lastFingerprint = fingerprint
        let sentences = sentenceLocator.sentences(in: text)
        state.preparePlayback(
            sourceApplication: sourceApplication,
            sentences: sentences
        )
        try speech.speak(text, sessionID: activeSpeechSessionID)
    }

    private func didStart(sessionID: SpeechSessionID) {
        guard sessionID == activeSpeechSessionID else {
            return
        }
        guard let source = state.sourceApplication else {
            fail(.speechFailed)
            return
        }
        state.beginPlayback(sourceApplication: source)
        switch state.onboardingStep {
        case .testSpeech:
            state.advanceOnboarding(after: .testSpeechSucceeded)
        case .practice:
            state.advanceOnboarding(after: .practicePlaybackStarted)
        default:
            break
        }
    }

    private func didComplete(sessionID: SpeechSessionID) {
        guard sessionID == activeSpeechSessionID else {
            return
        }
        state.completePlayback()
        completionGeneration += 1
        let generation = completionGeneration
        scheduleAfter(3) { [weak self] in
            guard let self, self.completionGeneration == generation else {
                return
            }
            self.lastFingerprint = nil
            self.state.stopPlayback()
        }
    }

    private func updateProgress(
        _ progress: Double,
        sessionID: SpeechSessionID
    ) {
        guard sessionID == activeSpeechSessionID else {
            return
        }
        state.updateProgress(progress)
    }

    private func fail(
        _ error: ReadingError,
        sessionID: SpeechSessionID? = nil
    ) {
        if let sessionID, sessionID != activeSpeechSessionID {
            return
        }
        state.showFailure(error)
    }

    private func reportClipboardError(_ error: ReadingError) {
        switch state.playbackState {
        case .preparing, .playing, .paused:
            state.showNonInterruptingError(error)
        default:
            fail(error)
        }
    }

    private func canToggleWhenSelectionIsUnavailable(
        _ error: ReadingError
    ) -> Bool {
        guard
            lastFingerprint != nil,
            state.playbackState == .playing
                || state.playbackState == .paused
        else {
            return false
        }
        return [
            .focusedElementUnavailable,
            .selectedTextUnsupported,
            .emptySelection
        ].contains(error)
    }
}
