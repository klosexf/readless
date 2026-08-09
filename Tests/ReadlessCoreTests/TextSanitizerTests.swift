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
                "字段甲\t字段乙\t字段丙\n数据甲\t数据乙\t数据丙\n数据丁\t数据戊\t数据己\n数据庚\t数据辛\t数据壬"
            ),
            """
            这是一个三列表格，共三行内容。
            列标题依次是：字段甲、字段乙、字段丙。
            第 1 行。
            字段甲：数据甲。
            字段乙：数据乙。
            字段丙：数据丙。
            第 2 行。
            字段甲：数据丁。
            字段乙：数据戊。
            字段丙：数据己。
            第 3 行。
            字段甲：数据庚。
            字段乙：数据辛。
            字段丙：数据壬。
            """
        )
    }

    func testFormatsEmptyAndURLOnlyCellsWithoutLosingColumnPosition() throws {
        XCTAssertEqual(
            try sanitizer.sanitize(
                "\t状态\t备注\n任务 A\t \thttps://example.com/a"
            ),
            """
            这是一个三列表格，共一行内容。
            列标题依次是：第 1 列、状态、备注。
            第 1 行。
            第 1 列：任务 A。
            状态：空白。
            备注：空白。
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

    func testFormatsHTMLTableAsGenericRows() throws {
        XCTAssertEqual(
            try sanitizer.sanitize(
                """
                <table>
                  <tr><th>字段甲</th><th>字段乙</th><th>字段丙</th></tr>
                  <tr><td>数据甲</td><td>数据乙</td><td><strong>数据丙</strong></td></tr>
                  <tr><td>数据丁</td><td>数据戊</td><td>数据己</td></tr>
                </table>
                """
            ),
            """
            这是一个三列表格，共二行内容。
            列标题依次是：字段甲、字段乙、字段丙。
            第 1 行。
            字段甲：数据甲。
            字段乙：数据乙。
            字段丙：数据丙。
            第 2 行。
            字段甲：数据丁。
            字段乙：数据戊。
            字段丙：数据己。
            """
        )
    }

    func testPreservesHTMLProseAroundTable() throws {
        XCTAssertEqual(
            try sanitizer.sanitize(
                """
                <p>前言内容。</p>
                <table><tr><th>字段甲</th><th>字段乙</th></tr><tr><td>数据甲</td><td>数据乙</td></tr></table>
                <p>结尾内容。</p>
                """
            ),
            """
            前言内容。

            这是一个二列表格，共一行内容。
            列标题依次是：字段甲、字段乙。
            第 1 行。
            字段甲：数据甲。
            字段乙：数据乙。

            结尾内容。
            """
        )
    }
}
