import AppKit
import SwiftUI

final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let state: ReadlessAppState

    init(
        state: ReadlessAppState,
        actions: ReadlessActions
    ) {
        self.state = state

        let hostingController = NSHostingController(
            rootView: MainWindowView(
                state: state,
                actions: actions
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )
        window.title = "桌面听读助手"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentMinSize = NSSize(width: 560, height: 460)
        window.contentMaxSize = NSSize(width: 640, height: 560)
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else {
            return
        }
        if !window.isVisible {
            window.center()
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        state.closeManagementWindow()
    }
}
