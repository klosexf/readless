import AppKit

@MainActor
final class SystemClipboardReader: ClipboardReading {
    func readString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}
