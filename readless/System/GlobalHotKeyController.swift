import Carbon.HIToolbox

@MainActor
final class GlobalHotKeyController {
    private static let signature: OSType = 0x52444C53
    private static let identifier: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        installEventHandler()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func register(
        _ configuration: HotKeyConfiguration
    ) -> Result<Void, ReadingError> {
        unregister()
        let identifier = EventHotKeyID(
            signature: Self.signature,
            id: Self.identifier
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

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    private func handle(_ identifier: EventHotKeyID) {
        guard
            identifier.signature == Self.signature,
            identifier.id == Self.identifier
        else {
            return
        }
        action()
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

    private nonisolated static let eventCallback:
        EventHandlerUPP = { _, event, userData in
            guard let event, let userData else {
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

            let controllerPointer = UInt(bitPattern: userData)
            let signature = identifier.signature
            let id = identifier.id
            Task { @MainActor in
                guard
                    let pointer = UnsafeRawPointer(
                        bitPattern: controllerPointer
                    )
                else {
                    return
                }
                let controller = Unmanaged<GlobalHotKeyController>
                    .fromOpaque(pointer)
                    .takeUnretainedValue()
                controller.handle(
                    EventHotKeyID(signature: signature, id: id)
                )
            }
            return noErr
        }
}
