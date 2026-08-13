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

    func testReaderFallsBackToValueAndSelectedRange() throws {
        let source = try readerSource()

        XCTAssertTrue(
            source.contains("private func selectedTextFromValueAndRange(")
        )
        XCTAssertTrue(source.contains("kAXValueAttribute"))
        XCTAssertTrue(source.contains("selectedRange(from: element)"))
        XCTAssertTrue(
            source.contains(
                "let valueAndRange = selectedTextFromValueAndRange"
            )
        )
        XCTAssertTrue(
            source.contains(
                "hasSelectionSurface =\n            hasSelectionSurface\n            || valueAndRange.hasSelectionSurface"
            )
        )
    }

    func testReaderExtractsPlainTextFromStringAndAttributedString() throws {
        let source = try readerSource()

        XCTAssertTrue(source.contains("private func plainText("))
        XCTAssertTrue(source.contains("value as? String"))
        XCTAssertTrue(source.contains("value as? NSAttributedString"))
        XCTAssertTrue(source.contains("attributed.string"))
    }

    func testReaderFallsBackToAttributedStringForMarkerRange() throws {
        let source = try readerSource()

        XCTAssertTrue(
            source.contains("\"AXStringForTextMarkerRange\"")
        )
        XCTAssertTrue(
            source.contains("\"AXAttributedStringForTextMarkerRange\"")
        )
        XCTAssertTrue(source.contains("plainText(from: attributedRaw)"))
    }

    func testReaderEnablesWebAccessibilityForChromium() throws {
        let source = try readerSource()

        XCTAssertTrue(
            source.contains("private func enableWebAccessibilityIfNeeded(")
        )
        XCTAssertTrue(source.contains("enabledWebAccessibilityPIDs"))
        XCTAssertTrue(source.contains("\"AXManualAccessibility\""))
        XCTAssertTrue(source.contains("\"AXEnhancedUserInterface\""))
        XCTAssertTrue(
            source.contains("enableWebAccessibilityIfNeeded(\n            for: focusedApp")
        )
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
