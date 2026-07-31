import XCTest
@testable import ReadlessCore

@MainActor
final class ReadingCoordinatorTests: XCTestCase {
    private let state = ReadlessAppState()
    private let permission = PermissionFake()
    private let selection = SelectionReaderFake()
    private let clipboard = ClipboardReaderFake()
    private let speech = SpeechEngineFake()
    private var scheduledAction: (@MainActor () -> Void)?
    private lazy var coordinator = ReadingCoordinator(
        state: state,
        permission: permission,
        selectionReader: selection,
        clipboardReader: clipboard,
        sanitizer: DefaultTextSanitizer(),
        speech: speech,
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

private final class SpeechEngineFake: SpeechEngine {
    var onStarted: (() -> Void)?
    var onCompleted: (() -> Void)?
    var onFailed: ((ReadingError) -> Void)?

    private(set) var spokenTexts: [String] = []
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var stopCount = 0
    private(set) var rates: [Float] = []

    func speak(_ text: String) throws {
        spokenTexts.append(text)
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

    func setRate(_ rate: Float) {
        rates.append(rate)
    }

    func start() {
        onStarted?()
    }

    func complete() {
        onCompleted?()
    }
}
