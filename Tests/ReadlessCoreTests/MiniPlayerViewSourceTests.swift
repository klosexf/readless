import Foundation
import XCTest
@testable import ReadlessCore

final class MiniPlayerViewSourceTests: XCTestCase {
    func testPlaybackStatusLabelUsesReadableSemiboldFont() throws {
        let source = try miniPlayerSource()
        let statusSection = try XCTUnwrap(
            source.components(
                separatedBy: "Text(state.playbackState.displayName)"
            )
            .dropFirst()
            .first?
            .components(separatedBy: "Slider(")
            .first
        )

        XCTAssertTrue(
            statusSection.contains(
                ".font(.system(size: 13, weight: .semibold))"
            )
        )
    }

    func testMiniPlayerPanelUsesBackgroundDraggingAndPreservesPosition() throws {
        let source = try miniPlayerPanelSource()

        XCTAssertTrue(source.contains("panel.isMovableByWindowBackground = true"))
        XCTAssertTrue(source.contains("private var hasInitialPosition = false"))
        XCTAssertTrue(
            source.contains(
                "if hasInitialPosition {\n" +
                    "            frame = NSRect(origin: panel.frame.origin, size: size)"
            )
        )
    }

    private func miniPlayerSource() throws -> String {
        try source(named: "readless/MiniPlayerView.swift")
    }

    private func miniPlayerPanelSource() throws -> String {
        try source(named: "readless/MiniPlayerPanelController.swift")
    }

    private func source(named path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
