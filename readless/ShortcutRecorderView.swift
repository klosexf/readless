import AppKit
import SwiftUI

struct ShortcutRecorderView: View {
    let displayName: String
    let onRecorded: (HotKeyConfiguration) -> Void
    let onRestoreDefault: () -> Void

    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 10) {
            Text("触发快捷键")
                .font(.system(size: 10, weight: .medium))

            Spacer()

            Text(isRecording ? "请按新的组合键" : displayName)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Color.primary.opacity(0.06))
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 7,
                        style: .continuous
                    )
                )

            Button(isRecording ? "取消" : "录制") {
                isRecording.toggle()
            }
            .buttonStyle(.bordered)

            Button("恢复 ⌥R") {
                isRecording = false
                onRestoreDefault()
            }
            .buttonStyle(.borderless)
        }
        .background {
            if isRecording {
                ShortcutKeyCaptureView(
                    onRecorded: {
                        isRecording = false
                        onRecorded($0)
                    },
                    onCancel: {
                        isRecording = false
                    }
                )
                .frame(width: 1, height: 1)
                .opacity(0.001)
            }
        }
    }
}

private struct ShortcutKeyCaptureView: NSViewRepresentable {
    let onRecorded: (HotKeyConfiguration) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        KeyCaptureNSView(
            onRecorded: onRecorded,
            onCancel: onCancel
        )
    }

    func updateNSView(
        _ nsView: KeyCaptureNSView,
        context: Context
    ) {
        nsView.onRecorded = onRecorded
        nsView.onCancel = onCancel
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class KeyCaptureNSView: NSView {
    var onRecorded: (HotKeyConfiguration) -> Void
    var onCancel: () -> Void

    override var acceptsFirstResponder: Bool { true }

    init(
        onRecorded: @escaping (HotKeyConfiguration) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onRecorded = onRecorded
        self.onCancel = onCancel
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
            return
        }

        let modifiers = hotKeyModifiers(event.modifierFlags)
        guard !modifiers.isEmpty else {
            NSSound.beep()
            return
        }

        let label = event.charactersIgnoringModifiers?
            .uppercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let label, !label.isEmpty else {
            NSSound.beep()
            return
        }

        onRecorded(
            HotKeyConfiguration(
                keyCode: UInt32(event.keyCode),
                modifiers: modifiers,
                keyLabel: label
            )
        )
    }

    private func hotKeyModifiers(
        _ flags: NSEvent.ModifierFlags
    ) -> HotKeyModifiers {
        var result: HotKeyModifiers = []
        if flags.contains(.command) {
            result.insert(.command)
        }
        if flags.contains(.option) {
            result.insert(.option)
        }
        if flags.contains(.control) {
            result.insert(.control)
        }
        if flags.contains(.shift) {
            result.insert(.shift)
        }
        return result
    }
}
