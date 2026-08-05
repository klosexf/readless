import Carbon.HIToolbox

@MainActor
final class GlobalHotKeyController {
    private static let signature: OSType = 0x52444C53

    private static var registry: [UInt32: () -> Void] = [:]
    private static var eventHandlerRef: EventHandlerRef?
    private static var eventHandlerInstalled = false

    private let identifier: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private let action: () -> Void

    init(identifier: UInt32, action: @escaping () -> Void) {
        self.identifier = identifier
        self.action = action
        Self.registry[identifier] = action
        Self.installSharedEventHandler()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }

    func register(
        _ configuration: HotKeyConfiguration
    ) -> Result<Void, ReadingError> {
        unregister()
        let identifier = EventHotKeyID(
            signature: Self.signature,
            id: self.identifier
        )
        let status = RegisterEventHotKey(
            configuration.keyCode,
            carbonModifiers(configuration.modifiers),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            hotKeyRef = nil
            return .failure(.hotKeyConflict)
        }
        return .success(())
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private static func installSharedEventHandler() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            sharedEventCallback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    private func carbonModifiers(
        _ modifiers: HotKeyModifiers
    ) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) {
            result |= UInt32(cmdKey)
        }
        if modifiers.contains(.option) {
            result |= UInt32(optionKey)
        }
        if modifiers.contains(.control) {
            result |= UInt32(controlKey)
        }
        if modifiers.contains(.shift) {
            result |= UInt32(shiftKey)
        }
        return result
    }

    private nonisolated static let sharedEventCallback:
        EventHandlerUPP = { _, event, _ in
            guard let event else {
                return OSStatus(eventNotHandledErr)
            }

            var identifier = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &identifier
            )
            guard status == noErr else {
                return status
            }

            let id = identifier.id
            Task { @MainActor in
                if let action = GlobalHotKeyController.registry[id] {
                    action()
                }
            }
            return noErr
        }
}
