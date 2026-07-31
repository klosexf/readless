import AppKit

final class MenuBarController: NSObject, NSMenuDelegate {
    private let state: ReadlessAppState
    private let statusItem: NSStatusItem
    private let showMainWindow: (ManagementSection) -> Void
    private let togglePlaybackAction: () -> Void
    private let readClipboardAction: () -> Void
    private var contextMenu: NSMenu?

    init(
        state: ReadlessAppState,
        showMainWindow: @escaping (ManagementSection) -> Void,
        togglePlayback: @escaping () -> Void,
        readClipboard: @escaping () -> Void
    ) {
        self.state = state
        self.showMainWindow = showMainWindow
        togglePlaybackAction = togglePlayback
        readClipboardAction = readClipboard
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        super.init()

        guard let button = statusItem.button else {
            return
        }

        button.image = NSImage(
            systemSymbolName: "waveform",
            accessibilityDescription: "桌面听读助手"
        )
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc
    private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu(relativeTo: sender)
        } else {
            state.closeContextMenu()
            showMainWindow(.currentPlayback)
        }
    }

    private func showContextMenu(relativeTo button: NSStatusBarButton) {
        state.showContextMenu()
        let menu = makeContextMenu()
        contextMenu = menu
        menu.delegate = self
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.minY - 4),
            in: button
        )
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for descriptor in state.contextMenuItems {
            switch descriptor.action {
            case .togglePlayback:
                menu.addItem(
                    makeItem(
                        title: descriptor.title,
                        action: #selector(togglePlayback)
                    )
                )
            case .readClipboard:
                menu.addItem(
                    makeItem(
                        title: descriptor.title,
                        action: #selector(readClipboard)
                    )
                )
            case .recentReadings:
                menu.addItem(makeRecentReadingsItem())
            case .voiceServiceSettings:
                menu.addItem(
                    makeItem(
                        title: descriptor.title,
                        action: #selector(openVoiceService)
                    )
                )
            case .quit:
                menu.addItem(.separator())
                menu.addItem(
                    makeItem(
                        title: descriptor.title,
                        action: #selector(quitApplication)
                    )
                )
            }
        }
        return menu
    }

    private func makeItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: ""
        )
        item.target = self
        return item
    }

    private func makeRecentReadingsItem() -> NSMenuItem {
        let root = NSMenuItem(
            title: "最近朗读",
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu()
        [
            "真正好的工具，应该在需要时出现…",
            "产品的核心不在于功能数量…",
            "Gatekeeper 对公开分发应用…"
        ].forEach { title in
            let item = NSMenuItem(
                title: title,
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        submenu.addItem(
            makeItem(
                title: "查看全部",
                action: #selector(openRecentReadings)
            )
        )
        root.submenu = submenu
        return root
    }

    func menuDidClose(_ menu: NSMenu) {
        state.closeContextMenu()
        contextMenu = nil
    }

    @objc private func togglePlayback() {
        togglePlaybackAction()
    }

    @objc private func readClipboard() {
        readClipboardAction()
    }

    @objc private func openRecentReadings() {
        showMainWindow(.recentReadings)
    }

    @objc private func openVoiceService() {
        showMainWindow(.voiceService)
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
}
