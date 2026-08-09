import Foundation
import XCTest
@testable import ReadlessCore

final class SystemClipboardReaderSourceTests: XCTestCase {
    func testClipboardReaderPrefersHTMLTableBeforePlainText() throws {
        let source = try systemClipboardReaderSource()
        let htmlRead = try XCTUnwrap(
            source.range(of: "if let htmlTable = htmlTableString()")
        )
        let plainTextRead = try XCTUnwrap(
            source.range(of: "NSPasteboard.general.string(forType: .string)")
        )

        XCTAssertLessThan(htmlRead.lowerBound, plainTextRead.lowerBound)
    }

    private func systemClipboardReaderSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(
                "readless/System/SystemClipboardReader.swift"
            ),
            encoding: .utf8
        )
    }
}
