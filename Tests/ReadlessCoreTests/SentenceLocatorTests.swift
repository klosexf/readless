import XCTest
@testable import ReadlessCore

final class SentenceLocatorTests: XCTestCase {
    private let locator = DefaultSentenceLocator()

    func testSplitsChineseSentencesByPunctuation() {
        let text = "第一句。第二句。第三句。"
        let sentences = locator.sentences(in: text)

        XCTAssertEqual(sentences.map(\.text), ["第一句。", "第二句。", "第三句。"])
    }

    func testIncludesClosingQuotesWithSentence() {
        let text = "他说：「AI 时代，MVP 这套打法失效了。」然后继续。"
        let sentences = locator.sentences(in: text)

        XCTAssertEqual(sentences.count, 2)
        XCTAssertEqual(sentences[0].text, "他说：「AI 时代，MVP 这套打法失效了。」")
        XCTAssertEqual(sentences[1].text, "然后继续。")
    }

    func testTreatsMixedPunctuationAsSentenceBoundaries() {
        let text = "这是什么？真的！没问题。"
        let sentences = locator.sentences(in: text)

        XCTAssertEqual(sentences.map(\.text), ["这是什么？", "真的！", "没问题。"])
    }

    func testTrailingTextWithoutTerminatorBecomesFinalSentence() {
        let text = "第一句。第二句没有标点"
        let sentences = locator.sentences(in: text)

        XCTAssertEqual(sentences.count, 2)
        XCTAssertEqual(sentences[0].text, "第一句。")
        XCTAssertEqual(sentences[1].text, "第二句没有标点")
    }

    func testRangesAreContiguousAndCoverFullText() {
        let text = "第一句。第二句。第三句。"
        let sentences = locator.sentences(in: text)

        var offset = 0
        for sentence in sentences {
            XCTAssertEqual(sentence.range.location, offset)
            offset += sentence.range.length
        }
        XCTAssertEqual(offset, text.utf16.count)
    }

    func testProgressMappingSelectsCorrectSentence() {
        let text = "第一句。第二句。第三句。"
        let sentences = locator.sentences(in: text)
        let totalLength = text.utf16.count

        func sentence(at progress: Double) -> String? {
            let offset = Int(Double(totalLength) * progress)
            return sentences.first { NSLocationInRange(offset, $0.range) }?.text
                ?? sentences.last?.text
        }

        XCTAssertEqual(sentence(at: 0), "第一句。")
        XCTAssertEqual(sentence(at: 0.5), "第二句。")
        XCTAssertEqual(sentence(at: 0.9), "第三句。")
        XCTAssertEqual(sentence(at: 1), "第三句。")
    }

    func testEnglishSentencesSplitOnBasicPunctuation() {
        let text = "Hello world. How are you? I am fine."
        let sentences = locator.sentences(in: text)

        XCTAssertEqual(sentences.count, 3)
        XCTAssertEqual(sentences[0].text, "Hello world.")
        XCTAssertEqual(sentences[1].text, "How are you?")
        XCTAssertEqual(sentences[2].text, "I am fine.")
    }

    func testDoesNotSplitOnDecimalPointWithoutWhitespace() {
        let text = "速度是 1.0 倍。"
        let sentences = locator.sentences(in: text)

        XCTAssertEqual(sentences.count, 1)
        XCTAssertEqual(sentences[0].text, "速度是 1.0 倍。")
    }
}
