import Foundation

struct HotKeyModifiers: OptionSet, Codable, Equatable, Sendable {
    let rawValue: UInt32

    static let command = Self(rawValue: 1 << 0)
    static let option = Self(rawValue: 1 << 1)
    static let control = Self(rawValue: 1 << 2)
    static let shift = Self(rawValue: 1 << 3)
}

struct HotKeyConfiguration: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: HotKeyModifiers
    let keyLabel: String

    static let defaultReadSelection = Self(
        keyCode: 15,
        modifiers: [.option],
        keyLabel: "R"
    )

    static let defaultReadClipboard = Self(
        keyCode: 15,
        modifiers: [.option, .shift],
        keyLabel: "R"
    )

    var displayName: String {
        [
            modifiers.contains(.control) ? "⌃" : "",
            modifiers.contains(.option) ? "⌥" : "",
            modifiers.contains(.shift) ? "⇧" : "",
            modifiers.contains(.command) ? "⌘" : "",
            keyLabel.uppercased()
        ].joined()
    }
}

final class HotKeyConfigurationStore {
    private let defaults: UserDefaults
    private let key = "readSelectionHotKey"
    private let clipboardKey = "readClipboardHotKey"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> HotKeyConfiguration {
        guard
            let data = defaults.data(forKey: key),
            let value = try? JSONDecoder().decode(
                HotKeyConfiguration.self,
                from: data
            )
        else {
            return .defaultReadSelection
        }
        return value
    }

    func save(_ value: HotKeyConfiguration) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    func loadClipboard() -> HotKeyConfiguration {
        guard
            let data = defaults.data(forKey: clipboardKey),
            let value = try? JSONDecoder().decode(
                HotKeyConfiguration.self,
                from: data
            )
        else {
            return .defaultReadClipboard
        }
        return value
    }

    func saveClipboard(_ value: HotKeyConfiguration) {
        defaults.set(try? JSONEncoder().encode(value), forKey: clipboardKey)
    }
}
