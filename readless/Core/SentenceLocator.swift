import Foundation

struct SentenceRange: Equatable, Sendable {
    let text: String
    let range: NSRange
}

protocol SentenceLocating {
    func sentences(in text: String) -> [SentenceRange]
}

struct DefaultSentenceLocator: SentenceLocating {
    func sentences(in text: String) -> [SentenceRange] {
        var result: [SentenceRange] = []
        var searchStart = text.startIndex

        while searchStart < text.endIndex {
            let rangeStart = searchStart
            var cursor = searchStart
            var foundTerminator = false

            while cursor < text.endIndex {
                let character = text[cursor]
                if character.isSentenceTerminator,
                   !(character == "." && isInternalDecimalPoint(at: cursor, in: text)) {
                    cursor = text.index(after: cursor)

                    while cursor < text.endIndex,
                          text[cursor].isClosingPunctuation {
                        cursor = text.index(after: cursor)
                    }

                    let contentEnd = cursor

                    while cursor < text.endIndex,
                          text[cursor].isWhitespace {
                        cursor = text.index(after: cursor)
                    }

                    let textRange = rangeStart..<cursor
                    let sentenceText = String(text[rangeStart..<contentEnd])
                        .trimmingCharacters(in: .whitespaces)
                    if !sentenceText.isEmpty {
                        result.append(SentenceRange(
                            text: sentenceText,
                            range: NSRange(textRange, in: text)
                        ))
                    }
                    searchStart = cursor
                    foundTerminator = true
                    break
                }
                cursor = text.index(after: cursor)
            }

            if !foundTerminator {
                let textRange = rangeStart..<text.endIndex
                let sentenceText = String(text[textRange])
                    .trimmingCharacters(in: .whitespaces)
                if !sentenceText.isEmpty {
                    result.append(SentenceRange(
                        text: sentenceText,
                        range: NSRange(textRange, in: text)
                    ))
                }
                break
            }
        }

        return result
    }

    private func isInternalDecimalPoint(
        at index: String.Index,
        in text: String
    ) -> Bool {
        guard index > text.startIndex else {
            return false
        }
        let previous = text.index(before: index)
        let next = text.index(after: index)
        guard next < text.endIndex else {
            return false
        }
        return text[previous].isLetterOrDigit && text[next].isLetterOrDigit
    }
}

private extension Character {
    var isSentenceTerminator: Bool {
        switch self {
        case "。", "．", ".", "！", "!", "？", "?", "；", ";", "…":
            return true
        default:
            return false
        }
    }

    var isClosingPunctuation: Bool {
        switch self {
        case "」", "』", "）", ")", "】", "]", "›", "»", "\"", "'":
            return true
        default:
            return false
        }
    }

    var isLetterOrDigit: Bool {
        isLetter || isNumber
    }
}
