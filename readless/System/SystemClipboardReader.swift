import AppKit

@MainActor
final class SystemClipboardReader: ClipboardReading {
    func readString() -> String? {
        if let htmlTable = htmlTableString() {
            return htmlTable
        }
        return NSPasteboard.general.string(forType: .string)
    }

    private func htmlTableString() -> String? {
        guard let data = NSPasteboard.general.data(forType: .html),
              let html = String(data: data, encoding: .utf8),
              html.range(
                of: #"<table\b"#,
                options: [.regularExpression, .caseInsensitive]
              ) != nil else {
            return nil
        }
        return html
    }
}
