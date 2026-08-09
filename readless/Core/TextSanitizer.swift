import Foundation

struct DefaultTextSanitizer: TextSanitizing {
    private let paragraphMarker = "\u{E000}"

    func sanitize(_ text: String) throws -> String {
        if let htmlReading = htmlTableReading(from: text) {
            return htmlReading
        }

        let normalized = normalizedLineEndings(text)

        if let formattedTable = formatTableIfPossible(normalized) {
            return formattedTable
        }

        return try sanitizeProse(normalized)
    }

    private func normalizedLineEndings(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func sanitizeProse(_ text: String) throws -> String {
        let normalized = text
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

    private func htmlTableReading(from html: String) -> String? {
        let tables = htmlTableMatches(in: html)
        guard !tables.isEmpty else {
            return nil
        }

        var readingParts = [String]()
        var cursor = html.startIndex

        for table in tables {
            if let prose = sanitizedHTMLProse(
                String(html[cursor..<table.range.lowerBound])
            ) {
                readingParts.append(prose)
            }

            guard let tableText = tabDelimitedTableText(
                from: table.contents
            ), let tableReading = formatTableIfPossible(tableText) else {
                return nil
            }
            readingParts.append(tableReading)
            cursor = table.range.upperBound
        }

        if let prose = sanitizedHTMLProse(String(html[cursor...])) {
            readingParts.append(prose)
        }

        return readingParts.joined(separator: "\n\n")
    }

    private func htmlTableMatches(
        in html: String
    ) -> [(range: Range<String.Index>, contents: String)] {
        let pattern = #"(?is)<table\b[^>]*>(.*?)</table\s*>"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)

        return expression.matches(in: html, range: fullRange).compactMap {
            match in
            guard let range = Range(match.range, in: html),
                  let contentsRange = Range(match.range(at: 1), in: html) else {
                return nil
            }
            return (range, String(html[contentsRange]))
        }
    }

    private func tabDelimitedTableText(from html: String) -> String? {
        let rowContents = capturedGroups(
            in: html,
            pattern: #"(?is)<tr\b[^>]*>(.*?)</tr\s*>"#
        )
        let rows = rowContents.map { row in
            capturedGroups(
                in: row,
                pattern: #"(?is)<t[hd]\b[^>]*>(.*?)</t[hd]\s*>"#
            ).map(htmlText)
        }

        guard rows.count >= 2,
              let columnCount = rows.first?.count,
              columnCount >= 2,
              rows.allSatisfy({ $0.count == columnCount }) else {
            return nil
        }

        return rows
            .map { $0.joined(separator: "\t") }
            .joined(separator: "\n")
    }

    private func sanitizedHTMLProse(_ html: String) -> String? {
        try? sanitizeProse(htmlText(html))
    }

    private func htmlText(_ html: String) -> String {
        let withoutNonContent = replacingMatches(
            in: html,
            pattern: #"(?is)<(script|style)\b[^>]*>.*?</\1\s*>"#,
            with: " "
        )
        let withBreaks = replacingMatches(
            in: withoutNonContent,
            pattern: #"(?is)<\s*(br|/p|/div|/li)\b[^>]*>"#,
            with: "\n"
        )
        let withoutTags = replacingMatches(
            in: withBreaks,
            pattern: #"(?is)<[^>]+>"#,
            with: " "
        )

        return decodeHTMLEntities(withoutTags)
    }

    private func capturedGroups(in text: String, pattern: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: fullRange).compactMap {
            match in
            guard let range = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[range])
        }
    }

    private func replacingMatches(
        in text: String,
        pattern: String,
        with replacement: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(
            in: text,
            range: fullRange,
            withTemplate: replacement
        )
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private func formatTableIfPossible(_ text: String) -> String? {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let trimmedLines = lines.drop(while: isBlankLine)
        let nonTrailingBlankLines = trimmedLines
            .reversed()
            .drop(while: isBlankLine)
            .reversed()

        guard nonTrailingBlankLines.count >= 2 else {
            return nil
        }

        let rows = nonTrailingBlankLines.map {
            $0.components(separatedBy: "\t")
        }
        guard let columnCount = rows.first?.count,
              columnCount >= 2,
              rows.allSatisfy({ $0.count == columnCount }) else {
            return nil
        }

        return makeGenericTableReading(rows: rows)
    }

    private func isBlankLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func makeGenericTableReading(rows: [[String]]) -> String {
        let headings = rows[0].enumerated().map { index, value in
            let cleaned = cleanTableCell(value)
            return cleaned == "空白" ? "第 \(index + 1) 列" : cleaned
        }
        let body = rows.dropFirst()
        var readingLines = [
            "这是一个\(chineseCount(headings.count))列表格，共\(chineseCount(body.count))行内容。",
            "列标题依次是：\(headings.joined(separator: "、"))。"
        ]

        for (rowIndex, row) in body.enumerated() {
            readingLines.append("第 \(rowIndex + 1) 行。")
            readingLines.append(
                contentsOf: zip(headings, row).map { heading, value in
                    "\(heading)：\(cleanTableCell(value))。"
                }
            )
        }

        return readingLines.joined(separator: "\n")
    }

    private func cleanTableCell(_ value: String) -> String {
        (try? sanitizeProse(value)) ?? "空白"
    }

    private func chineseCount(_ value: Int) -> String {
        let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        guard value < 100 else {
            return String(value)
        }
        guard value >= 10 else {
            return digits[value]
        }

        let tens = value / 10
        let ones = value % 10
        let tensText = tens == 1 ? "十" : "\(digits[tens])十"
        return ones == 0 ? tensText : "\(tensText)\(digits[ones])"
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
