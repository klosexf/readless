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

    private func miniPlayerSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(
                "readless/MiniPlayerView.swift"
            ),
            encoding: .utf8
        )
    }
}
