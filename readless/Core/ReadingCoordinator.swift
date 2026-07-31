import Foundation

@MainActor
final class ReadingCoordinator {
    private let state: ReadlessAppState
    private let permission: AccessibilityPermissionChecking
    private let selectionReader: SelectionReading
    private let clipboardReader: ClipboardReading
    private let sanitizer: TextSanitizing
    private let speech: SpeechEngine
    private let scheduleAfter: (
        TimeInterval,
        @escaping @MainActor () -> Void
    ) -> Void
    private var lastFingerprint: SelectionFingerprint?

    init(
        state: ReadlessAppState,
        permission: AccessibilityPermissionChecking,
        selectionReader: SelectionReading,
        clipboardReader: ClipboardReading,
        sanitizer: TextSanitizing,
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
        self.sanitizer = sanitizer
        self.speech = speech
        self.scheduleAfter = scheduleAfter ?? { delay, action in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                action()
            }
        }

        speech.onStarted = { [weak self] in
            self?.didStart()
        }
        speech.onCompleted = { [weak self] in
            self?.didComplete()
        }
        speech.onFailed = { [weak self] error in
            self?.fail(error)
        }
    }

    func handleReadShortcut() {
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

    func stop() {
        speech.stop()
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
        lastFingerprint = fingerprint
        state.preparePlayback(
            sourceApplication: sourceApplication,
            sentence: text
        )
        try speech.speak(text)
    }

    private func didStart() {
        guard
            let source = state.sourceApplication,
            let sentence = state.currentSentence
        else {
            fail(.speechFailed)
            return
        }
        state.beginPlayback(
            sourceApplication: source,
            sentence: sentence
        )
    }

    private func didComplete() {
        state.completePlayback()
        scheduleAfter(3) { [weak self] in
            self?.lastFingerprint = nil
            self?.state.stopPlayback()
        }
    }

    private func fail(_ error: ReadingError) {
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
