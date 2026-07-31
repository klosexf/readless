import XCTest
@testable import ReadlessCore

final class HotKeyConfigurationTests: XCTestCase {
    func testDefaultShortcutIsOptionR() {
        let shortcut = HotKeyConfiguration.defaultReadSelection

        XCTAssertEqual(shortcut.keyCode, 15)
        XCTAssertEqual(shortcut.modifiers, [.option])
        XCTAssertEqual(shortcut.displayName, "⌥R")
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
}
