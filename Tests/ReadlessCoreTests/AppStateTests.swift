import XCTest
@testable import ReadlessCore

final class AppStateTests: XCTestCase {
    func testDefaultStateIsQuietAndClosed() {
        let state = ReadlessAppState()

        XCTAssertEqual(state.playbackState, .idle)
        XCTAssertEqual(state.managementSection, .currentPlayback)
        XCTAssertFalse(state.isManagementWindowVisible)
        XCTAssertFalse(state.isContextMenuVisible)
        XCTAssertFalse(state.isMiniPlayerVisible)
        XCTAssertFalse(state.isMiniPlayerExpanded)
        XCTAssertTrue(state.showsCurrentSentence)
        XCTAssertEqual(state.materialMode, .automatic)
        XCTAssertFalse(state.isOnboardingVisible)
        XCTAssertEqual(state.onboardingStep, .configuration)
    }

    func testAccessibilityCannotAdvanceBeforeTestSpeechSuccess() {
        let state = ReadlessAppState()

        state.advanceOnboarding(after: .configurationSaved)
        state.advanceOnboarding(after: .accessibilityGranted)

        XCTAssertEqual(state.onboardingStep, .testSpeech)
    }

    func testLeftClickOpensManagementWindowAndClosesContextMenu() {
        let state = ReadlessAppState()
        state.showContextMenu()

        state.showManagementWindow()

        XCTAssertTrue(state.isManagementWindowVisible)
        XCTAssertFalse(state.isContextMenuVisible)
    }

    func testRightClickOpensContextMenuAndClosesManagementWindow() {
        let state = ReadlessAppState()
        state.showManagementWindow()

        state.showContextMenu()

        XCTAssertFalse(state.isManagementWindowVisible)
        XCTAssertTrue(state.isContextMenuVisible)
    }

    func testPlaybackCanPauseAndResume() {
        let state = ReadlessAppState()
        state.beginPlayback(
            sourceApplication: "Safari",
            sentence: "注意力不是无限资源。"
        )

        XCTAssertEqual(state.playbackState, .playing)
        XCTAssertTrue(state.isMiniPlayerVisible)

        state.togglePlayback()
        XCTAssertEqual(state.playbackState, .paused)

        state.togglePlayback()
        XCTAssertEqual(state.playbackState, .playing)
    }

    func testProgressSwitchesCurrentSentence() {
        let state = ReadlessAppState()
        let locator = DefaultSentenceLocator()
        let sentences = locator.sentences(
            in: "第一句。第二句。第三句。"
        )
        state.preparePlayback(
            sourceApplication: "Safari",
            sentences: sentences
        )
        state.beginPlayback(sourceApplication: "Safari")

        XCTAssertEqual(state.currentSentence, "第一句。")

        state.updateProgress(0.5)

        XCTAssertEqual(state.currentSentence, "第二句。")

        state.updateProgress(0.9)

        XCTAssertEqual(state.currentSentence, "第三句。")

        state.completePlayback()

        XCTAssertEqual(state.currentSentence, "第三句。")
    }

    func testCollapsedPlayerNeverExposesCurrentSentence() {
        let state = ReadlessAppState()
        state.beginPlayback(
            sourceApplication: "Safari",
            sentence: "注意力不是无限资源。"
        )

        XCTAssertNil(state.visibleCurrentSentence)

        state.setMiniPlayerExpanded(true)
        XCTAssertEqual(state.visibleCurrentSentence, "注意力不是无限资源。")

        state.showsCurrentSentence = false
        XCTAssertNil(state.visibleCurrentSentence)
    }

    func testChangingMaterialDoesNotChangePlaybackState() {
        let state = ReadlessAppState()
        state.beginPlayback(
            sourceApplication: "Safari",
            sentence: "注意力不是无限资源。"
        )
        state.progress = 0.42

        state.materialMode = .compatibility

        XCTAssertEqual(state.playbackState, .playing)
        XCTAssertEqual(state.progress, 0.42)
        XCTAssertTrue(state.isMiniPlayerVisible)
    }

    func testContextMenuPlaybackCommandReflectsCurrentState() {
        let state = ReadlessAppState()

        XCTAssertNil(state.contextMenuItems.first?.playbackCommandTitle)

        state.beginPlayback(
            sourceApplication: "Safari",
            sentence: "注意力不是无限资源。"
        )
        XCTAssertEqual(
            state.contextMenuItems.first?.playbackCommandTitle,
            "暂停朗读"
        )

        state.togglePlayback()
        XCTAssertEqual(
            state.contextMenuItems.first?.playbackCommandTitle,
            "继续朗读"
        )
    }

    func testPreparingShowsCompactPlayerWithoutInventingProgress() {
        let state = ReadlessAppState()

        state.preparePlayback(
            sourceApplication: "Safari",
            sentence: "测试"
        )

        XCTAssertEqual(state.playbackState, .preparing)
        XCTAssertTrue(state.isMiniPlayerVisible)
        XCTAssertEqual(state.progress, 0)
    }

    func testFailureKeepsCompactSurfaceVisibleAndStoresTypedError() {
        let state = ReadlessAppState()

        state.showFailure(.selectedTextUnsupported)

        XCTAssertEqual(state.playbackState, .failed)
        XCTAssertEqual(state.readingError, .selectedTextUnsupported)
        XCTAssertTrue(state.isMiniPlayerVisible)
    }

    func testCompletionCanReturnToIdle() {
        let state = ReadlessAppState()
        state.beginPlayback(
            sourceApplication: "Safari",
            sentence: "测试"
        )

        state.completePlayback()
        XCTAssertEqual(state.playbackState, .completed)

        state.stopPlayback()
        XCTAssertEqual(state.playbackState, .idle)
        XCTAssertFalse(state.isMiniPlayerVisible)
    }

    func testPlaybackAndErrorLabelsAreUserFacing() {
        XCTAssertEqual(PlaybackState.preparing.displayName, "正在准备")
        XCTAssertEqual(PlaybackState.paused.displayName, "已暂停")
        XCTAssertEqual(
            ReadingError.hotKeyConflict.userMessage,
            "快捷键已被占用，请设置新的快捷键。"
        )
    }

    func testDoubaoAPIKeyErrorExplainsWhichCredentialToUse() {
        XCTAssertEqual(
            ReadingError.doubaoAPIKeyInvalid.userMessage,
            "豆包 API Key 无效。请填写新版控制台“API Key 管理”中的 API Key，不要填写 Access Token。"
        )
    }

    func testRecentReadingsViewUsesPublishedStateInsteadOfSamples() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("readless/MainWindowView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("RecentReadingsView(state: state)"))
        XCTAssertFalse(source.contains("private let readings = ["))
    }
}
