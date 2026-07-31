import Foundation

struct DefaultTextSanitizer: TextSanitizing {
    private let paragraphMarker = "\u{E000}"

    func sanitize(_ text: String) throws -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(
                of: #"\n[ \t]*\n+"#,
                with: paragraphMarker,
                options: .regularExpression
            )

        let result = normalized
            .components(separatedBy: paragraphMarker)
            .map(cleanParagraph)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !result.isEmpty else {
            throw ReadingError.emptySelection
        }
        return result
    }

    private func cleanParagraph(_ paragraph: String) -> String {
        paragraph
            .split(
                separator: "\n",
                omittingEmptySubsequences: false
            )
            .map(String.init)
            .filter { !isStandaloneURL($0) }
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func isStandaloneURL(_ line: String) -> Bool {
        let candidate = line.trimmingCharacters(in: .whitespaces)
        return candidate.range(
            of: #"^https?://\S+$"#,
            options: .regularExpression
        ) != nil
    }
}
