import AppKit
import SwiftUI

private final class MiniPlayerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class MiniPlayerPanelController: NSWindowController {
    private let state: ReadlessAppState

    init(
        state: ReadlessAppState,
        actions: ReadlessActions
    ) {
        self.state = state

        let panel = MiniPlayerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        super.init(window: panel)
        panel.contentViewController = NSHostingController(
            rootView: MiniPlayerView(
                state: state,
                actions: actions,
                toggleExpanded: { [weak self] in
                    self?.toggleExpanded()
                }
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        resizeAndPosition(animated: false)
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    func refreshLayout(animated: Bool = true) {
        resizeAndPosition(animated: animated)
    }

    private func toggleExpanded() {
        state.setMiniPlayerExpanded(!state.isMiniPlayerExpanded)
        resizeAndPosition(animated: true)
    }

    private func resizeAndPosition(animated: Bool) {
        guard let panel = window as? NSPanel else {
            return
        }
        let isError = state.readingError != nil
        let size = NSSize(
            width: state.isMiniPlayerExpanded ? 620 : 580,
            height: isError
                ? 72
                : (state.isMiniPlayerExpanded ? 126 : 52)
        )
        let visibleFrame = panel.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 24
        )
        panel.setFrame(
            NSRect(origin: origin, size: size),
            display: true,
            animate: animated
        )
    }
}
