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
    }
}
