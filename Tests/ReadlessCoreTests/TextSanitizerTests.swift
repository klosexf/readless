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

    func testFormatsTabDelimitedTableAsGenericRows() throws {
        XCTAssertEqual(
            try sanitizer.sanitize(
                "项目\t第一遍\t第二遍\n字数\t905\t910\n例子\t0\t0"
            ),
            """
            这是一个 3 列、2 行的表格。

            列标题依次是：项目、第一遍、第二遍。

            第 1 行。项目：字数；第一遍：905；第二遍：910。

            第 2 行。项目：例子；第一遍：0；第二遍：0。

            表格朗读结束。
            """
        )
    }

    func testFormatsEmptyAndURLOnlyCellsWithoutLosingColumnPosition() throws {
        XCTAssertEqual(
            try sanitizer.sanitize(
                "\t状态\t备注\n任务 A\t \thttps://example.com/a"
            ),
            """
            这是一个 3 列、1 行的表格。

            列标题依次是：第 1 列、状态、备注。

            第 1 行。第 1 列：任务 A；状态：空白；备注：空白。

            表格朗读结束。
            """
        )
    }

    func testDoesNotFormatRowsWithInconsistentColumnCountsAsTable() throws {
        XCTAssertEqual(
            try sanitizer.sanitize("名称\t状态\n任务 A"),
            "名称 状态 任务 A"
        )
    }

    func testDoesNotFormatSingleTabDelimitedLineAsTable() throws {
        XCTAssertEqual(
            try sanitizer.sanitize("名称\t状态"),
            "名称 状态"
        )
    }

    func testPreservesExistingParagraphBehaviorForNonTableText() throws {
        XCTAssertEqual(
            try sanitizer.sanitize("第一段\n\n第二段"),
            "第一段\n\n第二段"
        )
    }
}
