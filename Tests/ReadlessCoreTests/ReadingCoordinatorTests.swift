import XCTest
@testable import ReadlessCore

@MainActor
final class ReadingCoordinatorTests: XCTestCase {
    private let state = ReadlessAppState()
    private let permission = PermissionFake()
    private let selection = SelectionReaderFake()
    private let clipboard = ClipboardReaderFake()
    private let speech = SpeechEngineFake()
    private let readiness = VoiceServiceReadinessFake()
    private let history = RecentReadingStoreFake()
    private var scheduledAction: (@MainActor () -> Void)?
    private lazy var coordinator = ReadingCoordinator(
        state: state,
        permission: permission,
        selectionReader: selection,
        clipboardReader: clipboard,
        voiceServiceReadiness: readiness,
        sanitizer: DefaultTextSanitizer(),
        sentenceLocator: DefaultSentenceLocator(),
        speech: speech,
        history: history,
        now: { Date(timeIntervalSince1970: 1_700_000_000) },
        scheduleAfter: { [weak self] _, action in
            self?.scheduledAction = action
        }
    )

    func testPermissionFailureDoesNotReadSelection() {
        permission.isTrusted = false

        coordinator.handleReadShortcut()

        XCTAssertEqual(
            state.readingError,
            .accessibilityPermissionRequired
        )
        XCTAssertEqual(selection.readCount, 0)
        XCTAssertEqual(permission.promptCount, 1)
    }

    func testUnconfiguredShortcutShowsConfigurationWithoutReadingSelection() {
        readiness.isReady = false

        coordinator.handleReadShortcut()

        XCTAssertEqual(selection.readCount, 0)
        XCTAssertTrue(state.isOnboardingVisible)
        XCTAssertEqual(state.onboardingStep, .configuration)
    }

    func testUnconfiguredClipboardReadShowsConfigurationWithoutReadingClipboard() {
        readiness.isReady = false
        clipboard.value = "不应读取"

        coordinator.readClipboard()

        XCTAssertEqual(clipboard.readCount, 0)
        XCTAssertTrue(state.isOnboardingVisible)
        XCTAssertEqual(state.onboardingStep, .configuration)
    }

    func testTestSpeechStartsBuiltInSentenceWithoutReadingSelection() {
        state.showOnboarding(at: .testSpeech)

        coordinator.readTestSpeech()

        XCTAssertEqual(selection.readCount, 0)
        XCTAssertEqual(speech.spokenTexts, ["你好，这是桌面听读助手的内置测试语音。"])
        speech.start()
        XCTAssertEqual(state.onboardingStep, .accessibility)
    }

    func testFailedTestSpeechStaysOnTestStep() {
        state.showOnboarding(at: .testSpeech)

        coordinator.readTestSpeech()
        speech.fail(.voiceServiceCredentialInvalid)

        XCTAssertEqual(state.onboardingStep, .testSpeech)
        XCTAssertEqual(state.readingError, .voiceServiceCredentialInvalid)
    }

    func testValidSelectionStartsSpeech() {
        selection.result = .success(firstSnapshot)

        coordinator.handleReadShortcut()

        XCTAssertEqual(speech.spokenTexts, ["原文"])
        XCTAssertEqual(state.playbackState, .preparing)

        speech.start()
        XCTAssertEqual(state.playbackState, .playing)
        XCTAssertTrue(state.isMiniPlayerVisible)
    }

    func testSameSelectionPausesThenResumes() {
        selection.result = .success(firstSnapshot)
        coordinator.handleReadShortcut()
        speech.start()

        coordinator.handleReadShortcut()

        XCTAssertEqual(speech.pauseCount, 1)
        XCTAssertEqual(state.playbackState, .paused)

        coordinator.handleReadShortcut()

        XCTAssertEqual(speech.resumeCount, 1)
        XCTAssertEqual(state.playbackState, .playing)
    }

    func testSpeechProgressUpdatesPlayerWhilePlaying() {
        selection.result = .success(firstSnapshot)
        coordinator.handleReadShortcut()
        speech.start()

        speech.emitProgress(0.42)

        XCTAssertEqual(state.progress, 0.42)
    }

    func testProgressUpdatesCurrentSentenceInExpandedPlayer() {
        let multiSentence = SelectionSnapshot(
            text: "第一句。第二句。第三句。",
            sourceApplication: "Safari",
            bundleIdentifier: "com.apple.Safari",
            selectionIdentifier: "1:1"
        )
        selection.result = .success(multiSentence)
        coordinator.handleReadShortcut()
        speech.start()
        state.setMiniPlayerExpanded(true)

        XCTAssertEqual(state.currentSentence, "第一句。")

        speech.emitProgress(0.5)

        XCTAssertEqual(state.currentSentence, "第二句。")

        speech.emitProgress(0.9)

        XCTAssertEqual(state.currentSentence, "第三句。")
    }

    func testSeekingUpdatesPlayerAndSpeechEngineWhilePlaying() {
        selection.result = .success(firstSnapshot)
        coordinator.handleReadShortcut()
        speech.start()

        coordinator.seek(to: 0.65)

        XCTAssertEqual(state.progress, 0.65)
        XCTAssertEqual(speech.seekProgresses, [0.65])
    }

    func testSeekingAfterCompletionRestartsPlaybackFromNewPosition() {
        selection.result = .success(firstSnapshot)
        coordinator.handleReadShortcut()
        speech.start()
        speech.complete()

        coordinator.seek(to: 0.25)

        XCTAssertEqual(state.playbackState, .playing)
        XCTAssertEqual(state.progress, 0.25)
        XCTAssertEqual(speech.seekProgresses, [0.25])

        scheduledAction?()
        XCTAssertEqual(state.playbackState, .playing)
    }

    func testNewSelectionReplacesSpeech() {
        selection.result = .success(firstSnapshot)
        coordinator.handleReadShortcut()
        speech.start()
        selection.result = .success(secondSnapshot)

        coordinator.handleReadShortcut()

        XCTAssertEqual(speech.stopCount, 1)
        XCTAssertEqual(speech.spokenTexts.last, "第二段")
        XCTAssertEqual(state.playbackState, .preparing)
    }

    func testLateCompletionFromReplacedSelectionDoesNotCompleteActivePlayback() throws {
        selection.result = .success(firstSnapshot)
        coordinator.handleReadShortcut()
        speech.start()
        let firstSessionID = try XCTUnwrap(speech.spokenSessionIDs.last)
        selection.result = .success(secondSnapshot)
        coordinator.handleReadShortcut()
        speech.start()

        speech.complete(sessionID: firstSessionID)

        XCTAssertEqual(state.playbackState, .playing)
        XCTAssertEqual(state.progress, 0)
    }

    func testSelectionFailureNeverReadsClipboard() {
        selection.result = .failure(.selectedTextUnsupported)

        coordinator.handleReadShortcut()

        XCTAssertEqual(clipboard.readCount, 0)
        XCTAssertEqual(
            state.readingError,
            .selectedTextUnsupported
        )
    }

    func testNoSelectionWhilePlayingTogglesPlayback() {
        selection.result = .success(firstSnapshot)
        coordinator.handleReadShortcut()
        speech.start()
        selection.result = .failure(.emptySelection)

        coordinator.handleReadShortcut()

        XCTAssertEqual(speech.pauseCount, 1)
        XCTAssertEqual(state.playbackState, .paused)
        XCTAssertEqual(clipboard.readCount, 0)
    }

    func testExplicitClipboardActionReadsOnce() {
        clipboard.value = "剪贴板文字"

        coordinator.readClipboard()

        XCTAssertEqual(clipboard.readCount, 1)
        XCTAssertEqual(speech.spokenTexts, ["剪贴板文字"])
    }

    func testStartedSelectionAddsRecentReading() {
        selection.result = .success(firstSnapshot)

        coordinator.handleReadShortcut()
        speech.start()

        XCTAssertEqual(history.readings.map(\.text), ["原文"])
        XCTAssertEqual(history.readings.first?.sourceApplication, "Safari")
        XCTAssertEqual(
            history.readings.first?.startedAt,
            Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testStartedClipboardAddsRecentReading() {
        clipboard.value = "剪贴板记录"

        coordinator.readClipboard()
        speech.start()

        XCTAssertEqual(history.readings.map(\.text), ["剪贴板记录"])
        XCTAssertEqual(history.readings.first?.sourceApplication, "剪贴板")
    }

    func testSpeechFailureBeforeStartDoesNotAddRecentReading() {
        selection.result = .success(firstSnapshot)

        coordinator.handleReadShortcut()
        speech.fail(.speechFailed)

        XCTAssertTrue(history.readings.isEmpty)
    }

    func testTestSpeechDoesNotAddRecentReading() {
        coordinator.readTestSpeech()
        speech.start()

        XCTAssertTrue(history.readings.isEmpty)
    }

    func testEmptyClipboardDoesNotReplaceActivePlayback() {
        selection.result = .success(firstSnapshot)
        coordinator.handleReadShortcut()
        speech.start()
        clipboard.value = nil

        coordinator.readClipboard()

        XCTAssertEqual(clipboard.readCount, 1)
        XCTAssertEqual(speech.stopCount, 0)
        XCTAssertEqual(state.readingError, .clipboardEmpty)
        XCTAssertEqual(state.playbackState, .playing)
    }

    func testStopCancelsSpeechAndHidesPlayer() {
        selection.result = .success(firstSnapshot)
        coordinator.handleReadShortcut()
        speech.start()

        coordinator.stop()

        XCTAssertEqual(speech.stopCount, 1)
        XCTAssertEqual(state.playbackState, .idle)
        XCTAssertFalse(state.isMiniPlayerVisible)
    }

    func testCompletionReturnsToIdleAfterScheduledDelay() {
        selection.result = .success(firstSnapshot)
        coordinator.handleReadShortcut()
        speech.start()

        speech.complete()

        XCTAssertEqual(state.playbackState, .completed)
        scheduledAction?()
        XCTAssertEqual(state.playbackState, .idle)
        XCTAssertFalse(state.isMiniPlayerVisible)
    }

    private var firstSnapshot: SelectionSnapshot {
        SelectionSnapshot(
            text: "原文",
            sourceApplication: "Safari",
            bundleIdentifier: "com.apple.Safari",
            selectionIdentifier: "4:2"
        )
    }

    private var secondSnapshot: SelectionSnapshot {
        SelectionSnapshot(
            text: "第二段",
            sourceApplication: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            selectionIdentifier: "8:3"
        )
    }
}

private final class PermissionFake:
    AccessibilityPermissionChecking
{
    var isTrusted = true
    private(set) var promptCount = 0

    func requestAccessPrompt() {
        promptCount += 1
    }
}

private final class VoiceServiceReadinessFake:
    VoiceServiceReadinessChecking
{
    var isReady = true

    var isReadyForSpeech: Bool {
        isReady
    }
}

private final class SelectionReaderFake: SelectionReading {
    var result: Result<SelectionSnapshot, ReadingError> = .failure(
        .selectedTextUnsupported
    )
    private(set) var readCount = 0

    func readSelection() throws -> SelectionSnapshot {
        readCount += 1
        return try result.get()
    }
}

private final class ClipboardReaderFake: ClipboardReading {
    var value: String?
    private(set) var readCount = 0

    func readString() -> String? {
        readCount += 1
        return value
    }
}

private final class RecentReadingStoreFake: RecentReadingStoring {
    private(set) var readings: [RecentReading] = []
    var appendError: Error?

    func load() throws -> [RecentReading] {
        readings
    }

    func append(_ reading: RecentReading) throws -> [RecentReading] {
        if let appendError {
            throw appendError
        }
        readings = Array(([reading] + readings).prefix(3))
        return readings
    }
}

private final class SpeechEngineFake: SpeechEngine {
    var onStarted: ((SpeechSessionID) -> Void)?
    var onCompleted: ((SpeechSessionID) -> Void)?
    var onFailed: ((SpeechSessionID, ReadingError) -> Void)?
    var onProgress: ((SpeechSessionID, Double) -> Void)?

    private(set) var spokenTexts: [String] = []
    private(set) var spokenSessionIDs: [SpeechSessionID] = []
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var stopCount = 0
    private(set) var rates: [Float] = []
    private(set) var seekProgresses: [Double] = []

    func speak(_ text: String, sessionID: SpeechSessionID) throws {
        spokenTexts.append(text)
        spokenSessionIDs.append(sessionID)
    }

    func pause() {
        pauseCount += 1
    }

    func resume() {
        resumeCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func seek(to progress: Double) {
        seekProgresses.append(progress)
    }

    func setRate(_ rate: Float) {
        rates.append(rate)
    }

    func start(sessionID: SpeechSessionID? = nil) {
        onStarted?(sessionID ?? spokenSessionIDs.last!)
    }

    func complete(sessionID: SpeechSessionID? = nil) {
        onCompleted?(sessionID ?? spokenSessionIDs.last!)
    }

    func emitProgress(
        _ progress: Double,
        sessionID: SpeechSessionID? = nil
    ) {
        onProgress?(sessionID ?? spokenSessionIDs.last!, progress)
    }

    func fail(
        _ error: ReadingError,
        sessionID: SpeechSessionID? = nil
    ) {
        onFailed?(sessionID ?? spokenSessionIDs.last!, error)
    }
}
