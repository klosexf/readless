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

    func readSelection() throws -> SelectionSnapshot {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw ReadingError.focusedApplicationUnavailable
        }

        let focusedApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let focusedElement = elementValue(
            kAXFocusedUIElementAttribute as CFString,
            from: focusedApp
        ) else {
            throw ReadingError.focusedElementUnavailable
        }

        let result: SelectedTextResult
        do {
            result = try selectedText(
                startingAt: focusedElement,
                maximumParentDepth: 5
            )
        } catch {
            guard let focusedWindow = elementValue(
                kAXFocusedWindowAttribute as CFString,
                from: focusedApp
            ) else {
                throw error
            }
            result = try selectedTextInSubtree(
                rootedAt: focusedWindow,
                maximumElementCount: 900,
                maximumDepth: 18
            )
        }
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
            queue.append(
                contentsOf: children.map {
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
            if let text = nonEmptyString(rawText) {
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

        let rawText = parameterizedValue(
            "AXStringForTextMarkerRange" as CFString,
            parameter: markerRange,
            from: element
        )
        return nonEmptyString(rawText)
    }

    private func nonEmptyString(
        _ value: CFTypeRef?
    ) -> String? {
        guard
            let text = value as? String,
            !text.trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines
            ).isEmpty
        else {
            return nil
        }
        return text
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
