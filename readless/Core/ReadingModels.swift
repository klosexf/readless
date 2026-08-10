import Foundation

typealias SpeechSessionID = Int

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
    case voiceServiceNotConfigured
    case voiceServiceNetworkUnavailable
    case voiceServiceCredentialInvalid
    case doubaoAPIKeyInvalid
    case voiceServiceQuotaExceeded
    case voiceServiceTimedOut
    case voiceServiceResponseInvalid
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

struct RecentReading: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let text: String
    let sourceApplication: String
    let startedAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        sourceApplication: String,
        startedAt: Date
    ) {
        self.id = id
        self.text = text
        self.sourceApplication = sourceApplication
        self.startedAt = startedAt
    }
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

@MainActor
protocol RecentReadingStoring {
    func load() throws -> [RecentReading]
    func append(_ reading: RecentReading) throws -> [RecentReading]
}

protocol TextSanitizing {
    func sanitize(_ text: String) throws -> String
}

@MainActor
protocol SpeechEngine: AnyObject {
    var onStarted: ((SpeechSessionID) -> Void)? { get set }
    var onCompleted: ((SpeechSessionID) -> Void)? { get set }
    var onFailed: ((SpeechSessionID, ReadingError) -> Void)? { get set }
    var onProgress: ((SpeechSessionID, Double) -> Void)? { get set }

    func speak(_ text: String, sessionID: SpeechSessionID) throws
    func pause()
    func resume()
    func stop()
    func seek(to progress: Double)
    func setRate(_ rate: Float)
}
