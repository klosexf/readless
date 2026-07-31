import XCTest
@testable import ReadlessCore

final class TextSanitizerTests: XCTestCase {
    private let sanitizer = DefaultTextSanitizer()

    func testTrimsAndCollapsesInlineWhitespace() throws {
        XCTAssertEqual(
            try sanitizer.sanitize("  你好   世界  "),
            "你好 世界"
        )
    }

    func testMergesSingleHardLineBreaks() throws {
        XCTAssertEqual(
            try sanitizer.sanitize("第一行\n第二行"),
            "第一行 第二行"
        )
    }

    func testPreservesParagraphBreaks() throws {
        XCTAssertEqual(
            try sanitizer.sanitize("第一段。\n\n第二段。"),
            "第一段。\n\n第二段。"
        )
    }

    func testDropsStandaloneURLLines() throws {
        XCTAssertEqual(
            try sanitizer.sanitize(
                "正文\nhttps://example.com/a\n继续正文"
            ),
            "正文 继续正文"
        )
    }

    func testEmptyResultThrows() {
        XCTAssertThrowsError(
            try sanitizer.sanitize(" \n https://x.test ")
        ) {
            XCTAssertEqual($0 as? ReadingError, .emptySelection)
        }
    }
}
