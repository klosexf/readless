import Foundation
import XCTest

final class AccessibilitySelectionReaderSourceTests: XCTestCase {
    func testReaderSearchesFocusedWindowWhenFocusedElementIsUnavailable() throws {
        let source = try readerSource()

        XCTAssertTrue(source.contains("if let focusedElement {"))
        XCTAssertTrue(
            source.contains(
                "else {\n            result = try selectedTextInFocusedWindow"
            )
        )
        XCTAssertTrue(source.contains("private func selectedTextInFocusedWindow("))
    }

    func testSubtreeReaderCapsQueuedElementsAtMaximumCount() throws {
        let source = try readerSource()

        XCTAssertTrue(
            source.contains(
                "let remainingCapacity = maximumElementCount - queue.count"
            )
        )
        XCTAssertTrue(source.contains("children.prefix(remainingCapacity)"))
    }

    private func readerSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(
                "readless/System/AccessibilitySelectionReader.swift"
            ),
            encoding: .utf8
        )
    }
}
