import AppKit
import ApplicationServices

@MainActor
final class AccessibilityPermissionController:
    AccessibilityPermissionChecking
{
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessPrompt() {
        let promptKey =
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        guard !isTrusted,
              let settingsURL = URL(
                  string: "x-apple.systempreferences:"
                      + "com.apple.preference.security"
                      + "?Privacy_Accessibility"
              )
        else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
    }
}
