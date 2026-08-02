import XCTest
@testable import ReadlessCore

final class HotKeyConfigurationTests: XCTestCase {
    func testDefaultShortcutIsOptionR() {
        let shortcut = HotKeyConfiguration.defaultReadSelection

        XCTAssertEqual(shortcut.keyCode, 15)
        XCTAssertEqual(shortcut.modifiers, [.option])
        XCTAssertEqual(shortcut.displayName, "⌥R")
    }

    func testDefaultClipboardShortcutIsOptionShiftR() {
        let shortcut = HotKeyConfiguration.defaultReadClipboard

        XCTAssertEqual(shortcut.keyCode, 15)
        XCTAssertEqual(shortcut.modifiers, [.option, .shift])
        XCTAssertEqual(shortcut.displayName, "⌥⇧R")
    }

    func testShortcutRoundTripsThroughStore() {
        let suiteName = "ReadlessTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = HotKeyConfigurationStore(defaults: defaults)
        let shortcut = HotKeyConfiguration(
            keyCode: 1,
            modifiers: [.command, .shift],
            keyLabel: "S"
        )

        store.save(shortcut)

        XCTAssertEqual(store.load(), shortcut)
    }

    func testClipboardShortcutRoundTripsWithoutReplacingSelectionShortcut() {
        let suiteName = "ReadlessTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = HotKeyConfigurationStore(defaults: defaults)
        let selection = HotKeyConfiguration(
            keyCode: 1,
            modifiers: [.command, .shift],
            keyLabel: "S"
        )
        let clipboard = HotKeyConfiguration(
            keyCode: 9,
            modifiers: [.option, .shift],
            keyLabel: "V"
        )

        store.save(selection)
        store.saveClipboard(clipboard)

        XCTAssertEqual(store.load(), selection)
        XCTAssertEqual(store.loadClipboard(), clipboard)
    }
}
