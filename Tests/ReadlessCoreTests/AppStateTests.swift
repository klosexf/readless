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
            "⌥R 已被占用，请设置新的快捷键。"
        )
    }
}
