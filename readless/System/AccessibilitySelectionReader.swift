import AppKit
import ApplicationServices

@MainActor
final class AccessibilitySelectionReader: SelectionReading {
    private struct SelectedTextResult {
        let text: String
        let identifier: String?
    }

    private struct QueuedElement {
        let element: AXUIElement
        let depth: Int
    }

    private static var enabledWebAccessibilityPIDs: Set<pid_t> = []

    func readSelection() throws -> SelectionSnapshot {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw ReadingError.focusedApplicationUnavailable
        }

        let focusedApp = AXUIElementCreateApplication(app.processIdentifier)
        enableWebAccessibilityIfNeeded(
            for: focusedApp,
            pid: app.processIdentifier
        )
        let focusedElement = elementValue(
            kAXFocusedUIElementAttribute as CFString,
            from: focusedApp
        )

        let result: SelectedTextResult
        if let focusedElement {
            do {
                result = try selectedText(
                    startingAt: focusedElement,
                    maximumParentDepth: 5
                )
            } catch {
                result = try selectedTextInFocusedWindow(
                    from: focusedApp,
                    fallbackError: error
                )
            }
        } else {
            result = try selectedTextInFocusedWindow(
                from: focusedApp
            )
        }
        return SelectionSnapshot(
            text: result.text,
            sourceApplication: app.localizedName ?? "未知应用",
            bundleIdentifier: app.bundleIdentifier ?? "unknown",
            selectionIdentifier: result.identifier
        )
    }

    private func enableWebAccessibilityIfNeeded(
        for app: AXUIElement,
        pid: pid_t
    ) {
        guard !Self.enabledWebAccessibilityPIDs.contains(pid) else {
            return
        }
        Self.enabledWebAccessibilityPIDs.insert(pid)

        let manual = "AXManualAccessibility" as CFString
        let enhanced = "AXEnhancedUserInterface" as CFString

        var enabled = AXUIElementSetAttributeValue(
            app,
            manual,
            kCFBooleanTrue
        ) == .success
        if !enabled {
            enabled = AXUIElementSetAttributeValue(
                app,
                enhanced,
                kCFBooleanTrue
            ) == .success
        }

        guard enabled else {
            return
        }

        // 让 Chromium/Electron 异步构建网页内容 AX 树后再读取
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    private func selectedTextInFocusedWindow(
        from app: AXUIElement,
        fallbackError: Error = ReadingError.focusedElementUnavailable
    ) throws -> SelectedTextResult {
        guard let focusedWindow = elementValue(
            kAXFocusedWindowAttribute as CFString,
            from: app
        ) else {
            throw fallbackError
        }
        return try selectedTextInSubtree(
            rootedAt: focusedWindow,
            maximumElementCount: 900,
            maximumDepth: 18
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

            let candidateResult = selectedTextCandidate(
                from: candidate
            )
            foundEmptySelection =
                foundEmptySelection
                || candidateResult.hasSelectionSurface
            if let result = candidateResult.result {
                return result
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

    private func selectedTextInSubtree(
        rootedAt root: AXUIElement,
        maximumElementCount: Int,
        maximumDepth: Int
    ) throws -> SelectedTextResult {
        var queue = [
            QueuedElement(element: root, depth: 0)
        ]
        var currentIndex = 0
        var foundEmptySelection = false

        while currentIndex < queue.count,
              currentIndex < maximumElementCount {
            let queued = queue[currentIndex]
            currentIndex += 1

            let candidateResult = selectedTextCandidate(
                from: queued.element
            )
            foundEmptySelection =
                foundEmptySelection
                || candidateResult.hasSelectionSurface
            if let result = candidateResult.result {
                return result
            }

            guard queued.depth < maximumDepth else {
                continue
            }
            let children = elementValues(
                kAXChildrenAttribute as CFString,
                from: queued.element
            )
            let remainingCapacity = maximumElementCount - queue.count
            guard remainingCapacity > 0 else {
                continue
            }
            queue.append(
                contentsOf: children.prefix(remainingCapacity).map {
                    QueuedElement(
                        element: $0,
                        depth: queued.depth + 1
                    )
                }
            )
        }

        throw foundEmptySelection
            ? ReadingError.emptySelection
            : ReadingError.selectedTextUnsupported
    }

    private func selectedTextCandidate(
        from element: AXUIElement
    ) -> (
        result: SelectedTextResult?,
        hasSelectionSurface: Bool
    ) {
        var hasSelectionSurface = false

        if let rawText = value(
            kAXSelectedTextAttribute as CFString,
            from: element
        ) {
            hasSelectionSurface = true
            if let text = plainText(from: rawText) {
                return (
                    SelectedTextResult(
                        text: text,
                        identifier: diagnosticIdentifier(
                            for: element
                        )
                    ),
                    true
                )
            }
        }

        if value(
            "AXSelectedTextMarkerRange" as CFString,
            from: element
        ) != nil {
            hasSelectionSurface = true
            if let text = selectedTextFromMarkerRange(
                from: element
            ) {
                return (
                    SelectedTextResult(
                        text: text,
                        identifier: diagnosticIdentifier(
                            for: element
                        )
                    ),
                    true
                )
            }
        }

        let valueAndRange = selectedTextFromValueAndRange(
            from: element
        )
        hasSelectionSurface =
            hasSelectionSurface
            || valueAndRange.hasSelectionSurface
        if let text = valueAndRange.text {
            return (
                SelectedTextResult(
                    text: text,
                    identifier: diagnosticIdentifier(
                        for: element
                    )
                ),
                true
            )
        }

        return (nil, hasSelectionSurface)
    }

    private func selectedTextFromMarkerRange(
        from element: AXUIElement
    ) -> String? {
        guard let markerRange = value(
            "AXSelectedTextMarkerRange" as CFString,
            from: element
        ) else {
            return nil
        }

        let stringRaw = parameterizedValue(
            "AXStringForTextMarkerRange" as CFString,
            parameter: markerRange,
            from: element
        )
        if let text = plainText(from: stringRaw) {
            return text
        }

        let attributedRaw = parameterizedValue(
            "AXAttributedStringForTextMarkerRange" as CFString,
            parameter: markerRange,
            from: element
        )
        return plainText(from: attributedRaw)
    }

    private func selectedTextFromValueAndRange(
        from element: AXUIElement
    ) -> (text: String?, hasSelectionSurface: Bool) {
        guard value(
            kAXValueAttribute as CFString,
            from: element
        ) != nil else {
            return (nil, false)
        }

        guard let range = selectedRange(from: element),
              range.length > 0 else {
            return (nil, true)
        }

        guard let fullText = plainText(
            from: value(kAXValueAttribute as CFString, from: element)
        ) else {
            return (nil, true)
        }

        let nsValue = fullText as NSString
        let safeLocation = max(0, range.location)
        let safeLength = max(
            0,
            min(range.length, nsValue.length - safeLocation)
        )
        guard safeLength > 0 else {
            return (nil, true)
        }

        let substring = nsValue.substring(
            with: NSRange(location: safeLocation, length: safeLength)
        )
        return (nonEmptyString(substring), true)
    }

    private func nonEmptyString(
        _ text: String
    ) -> String? {
        let trimmed = text.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines
        )
        return trimmed.isEmpty ? nil : text
    }

    private func plainText(
        from value: CFTypeRef?
    ) -> String? {
        guard let value else {
            return nil
        }
        if let text = value as? String {
            return nonEmptyString(text)
        }
        if let attributed = value as? NSAttributedString {
            return nonEmptyString(attributed.string)
        }
        return nil
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

    private func elementValues(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> [AXUIElement] {
        value(attribute, from: element) as? [AXUIElement] ?? []
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

    private func parameterizedValue(
        _ attribute: CFString,
        parameter: CFTypeRef,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            attribute,
            parameter,
            &result
        ) == .success else {
            return nil
        }
        return result
    }
}
