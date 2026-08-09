import Foundation

struct DefaultTextSanitizer: TextSanitizing {
    private let paragraphMarker = "\u{E000}"

    func sanitize(_ text: String) throws -> String {
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
        let body = rows.dropFirst().enumerated().map { rowIndex, row in
            let fields = zip(headings, row).map { heading, value in
                "\(heading)：\(cleanTableCell(value))"
            }
            return "第 \(rowIndex + 1) 行。\(fields.joined(separator: "；"))。"
        }

        return ([
            "这是一个 \(headings.count) 列、\(body.count) 行的表格。",
            "列标题依次是：\(headings.joined(separator: "、"))。"
        ] + body + ["表格朗读结束。"])
            .joined(separator: "\n\n")
    }

    private func cleanTableCell(_ value: String) -> String {
        (try? sanitizeProse(value)) ?? "空白"
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
