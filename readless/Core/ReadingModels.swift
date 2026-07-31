import Foundation

enum ReadingError: String, Error, Equatable, Sendable {
    case accessibilityPermissionRequired
    case focusedApplicationUnavailable
    case focusedElementUnavailable
    case selectedTextUnsupported
    case emptySelection
    case clipboardEmpty
    case hotKeyConflict
    case speechUnavailable
    case speechFailed
}

struct SelectionSnapshot: Equatable, Sendable {
    let text: String
    let sourceApplication: String
    let bundleIdentifier: String
    let selectionIdentifier: String?
}

struct SelectionFingerprint: Hashable, Sendable {
    let sanitizedText: String
    let bundleIdentifier: String
    let selectionIdentifier: String?
}

@MainActor
protocol AccessibilityPermissionChecking {
    var isTrusted: Bool { get }
    func requestAccessPrompt()
}

@MainActor
protocol SelectionReading {
    func readSelection() throws -> SelectionSnapshot
}

@MainActor
protocol ClipboardReading {
    func readString() -> String?
}

protocol TextSanitizing {
    func sanitize(_ text: String) throws -> String
}

@MainActor
protocol SpeechEngine: AnyObject {
    var onStarted: (() -> Void)? { get set }
    var onCompleted: (() -> Void)? { get set }
    var onFailed: ((ReadingError) -> Void)? { get set }

    func speak(_ text: String) throws
    func pause()
    func resume()
    func stop()
    func setRate(_ rate: Float)
}
