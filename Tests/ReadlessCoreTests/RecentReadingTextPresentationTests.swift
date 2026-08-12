import XCTest
@testable import ReadlessCore

final class RecentReadingTextPresentationTests: XCTestCase {
    func testShortTextIsNotCollapsibleAndKeepsFullText() {
        let presentation = RecentReadingTextPresentation(text: "短文本")

        XCTAssertFalse(presentation.isCollapsible)
        XCTAssertEqual(presentation.collapsedText, "短文本")
    }

    func testTextAtCharacterLimitIsNotCollapsible() {
        let text = String(repeating: "阅", count: 160)
        let presentation = RecentReadingTextPresentation(text: text)

        XCTAssertFalse(presentation.isCollapsible)
        XCTAssertEqual(presentation.collapsedText, text)
    }

    func testTextBeyondCharacterLimitUsesFirst160CharactersAndEllipsis() {
        let text = String(repeating: "读", count: 161)
        let presentation = RecentReadingTextPresentation(text: text)

        XCTAssertTrue(presentation.isCollapsible)
        XCTAssertEqual(
            presentation.collapsedText,
            String(repeating: "读", count: 160) + "…"
        )
    }
}
