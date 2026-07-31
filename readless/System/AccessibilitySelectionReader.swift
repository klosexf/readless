import AppKit
import ApplicationServices

@MainActor
final class AccessibilitySelectionReader: SelectionReading {
    private struct SelectedTextResult {
        let text: String
        let identifier: String?
    }

    func readSelection() throws -> SelectionSnapshot {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw ReadingError.focusedApplicationUnavailable
        }

        let systemWide = AXUIElementCreateSystemWide()
        guard let focusedApp = elementValue(
            kAXFocusedApplicationAttribute as CFString,
            from: systemWide
        ) else {
            throw ReadingError.focusedApplicationUnavailable
        }
        guard let focusedElement = elementValue(
            kAXFocusedUIElementAttribute as CFString,
            from: focusedApp
        ) else {
            throw ReadingError.focusedElementUnavailable
        }

        let result = try selectedText(
            startingAt: focusedElement,
            maximumParentDepth: 5
        )
        return SelectionSnapshot(
            text: result.text,
            sourceApplication: app.localizedName ?? "未知应用",
            bundleIdentifier: app.bundleIdentifier ?? "unknown",
            selectionIdentifier: result.identifier
        )
    }

    private func selectedText(
        startingAt element: AXUIElement,
        maximumParentDepth: Int
    ) throws -> SelectedTextResult {
        var current: AXUIElement? = element
        var foundEmptySelection = false

        for _ in 0...maximumParentDepth {
            guard let candidate = current else {
                break
            }

            if let rawText = value(
                kAXSelectedTextAttribute as CFString,
                from: candidate
            ) {
                foundEmptySelection = true
                if let text = rawText as? String,
                   !text.trimmingCharacters(
                       in: CharacterSet.whitespacesAndNewlines
                   ).isEmpty {
                    return SelectedTextResult(
                        text: text,
                        identifier: diagnosticIdentifier(
                            for: candidate
                        )
                    )
                }
            }

            current = elementValue(
                kAXParentAttribute as CFString,
                from: candidate
            )
        }

        throw foundEmptySelection
            ? ReadingError.emptySelection
            : ReadingError.selectedTextUnsupported
    }

    private func diagnosticIdentifier(
        for element: AXUIElement
    ) -> String? {
        let role = value(
            kAXRoleAttribute as CFString,
            from: element
        ) as? String
        let subrole = value(
            kAXSubroleAttribute as CFString,
            from: element
        ) as? String
        let range = selectedRange(from: element)
        let parts: [String?] = [
            role,
            subrole,
            range.map { "\($0.location):\($0.length)" }
        ]
        let identifier = parts.compactMap { $0 }.joined(separator: "|")
        return identifier.isEmpty ? nil : identifier
    }

    private func selectedRange(
        from element: AXUIElement
    ) -> CFRange? {
        guard
            let rawValue = value(
                kAXSelectedTextRangeAttribute as CFString,
                from: element
            ),
            CFGetTypeID(rawValue) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = unsafeBitCast(rawValue, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    private func elementValue(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> AXUIElement? {
        guard
            let rawValue = value(attribute, from: element),
            CFGetTypeID(rawValue) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeBitCast(rawValue, to: AXUIElement.self)
    }

    private func value(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute,
            &result
        ) == .success else {
            return nil
        }
        return result
    }
}
