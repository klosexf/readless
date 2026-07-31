import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = ReadlessAppState()
    private let hotKeyStore = HotKeyConfigurationStore()
    private var menuBarController: MenuBarController?
    private var mainWindowController: MainWindowController?
    private var miniPlayerPanelController: MiniPlayerPanelController?
    private var permissionController:
        AccessibilityPermissionController?
    private var readingCoordinator: ReadingCoordinator?
    private var hotKeyController: GlobalHotKeyController?
    private var escapeKeyMonitor: EscapeKeyMonitor?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let permissionController =
            AccessibilityPermissionController()
        let speechEngine = SystemSpeechEngine()
        let coordinator = ReadingCoordinator(
            state: state,
            permission: permissionController,
            selectionReader: AccessibilitySelectionReader(),
            clipboardReader: SystemClipboardReader(),
            sanitizer: DefaultTextSanitizer(),
            speech: speechEngine
        )
        let hotKeyController = GlobalHotKeyController {
            coordinator.handleReadShortcut()
        }
        let escapeKeyMonitor = EscapeKeyMonitor {
            coordinator.stop()
        }

        self.permissionController = permissionController
        readingCoordinator = coordinator
        self.hotKeyController = hotKeyController
        self.escapeKeyMonitor = escapeKeyMonitor

        let actions = ReadlessActions(
            togglePlayback: {
                coordinator.togglePlayback()
            },
            stopPlayback: {
                coordinator.stop()
            },
            readClipboard: {
                coordinator.readClipboard()
            },
            requestAccessibility: {
                permissionController.requestAccessPrompt()
            },
            dismissError: { [weak self] in
                self?.state.dismissReadingError()
            },
            updateHotKey: { [weak self] configuration in
                self?.updateHotKey(configuration)
            },
            setRate: {
                coordinator.setRate($0)
            },
            openCurrentPlayback: { [weak self] in
                self?.showMainWindow(section: .currentPlayback)
            }
        )

        let mainWindowController = MainWindowController(
            state: state,
            actions: actions
        )
        let miniPlayerPanelController =
            MiniPlayerPanelController(
                state: state,
                actions: actions
            )

        self.mainWindowController = mainWindowController
        self.miniPlayerPanelController = miniPlayerPanelController
        menuBarController = MenuBarController(
            state: state,
            showMainWindow: { [weak self] section in
                self?.showMainWindow(section: section)
            },
            togglePlayback: actions.togglePlayback,
            readClipboard: actions.readClipboard
        )

        bindRuntimeSurfaces(
            miniPlayer: miniPlayerPanelController,
            escapeMonitor: escapeKeyMonitor
        )
        registerSavedHotKey()
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    private func showMainWindow(section: ManagementSection) {
        state.showManagementWindow(section: section)
        mainWindowController?.show()
    }

    private func registerSavedHotKey() {
        let configuration = hotKeyStore.load()
        state.hotKeyDisplayName = configuration.displayName
        if case .failure(let error) =
            hotKeyController?.register(configuration) {
            state.showFailure(error)
        }
    }

    private func updateHotKey(
        _ candidate: HotKeyConfiguration
    ) {
        guard let hotKeyController else {
            return
        }
        let previous = hotKeyStore.load()
        switch hotKeyController.register(candidate) {
        case .success:
            hotKeyStore.save(candidate)
            state.hotKeyDisplayName = candidate.displayName
            if state.readingError == .hotKeyConflict {
                state.dismissReadingError()
            }
        case .failure:
            _ = hotKeyController.register(previous)
            state.hotKeyDisplayName = previous.displayName
            switch state.playbackState {
            case .preparing, .playing, .paused:
                state.showNonInterruptingError(.hotKeyConflict)
            default:
                state.showFailure(.hotKeyConflict)
            }
        }
    }

    private func bindRuntimeSurfaces(
        miniPlayer: MiniPlayerPanelController,
        escapeMonitor: EscapeKeyMonitor
    ) {
        state.$isMiniPlayerVisible
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { isVisible in
                if isVisible {
                    miniPlayer.show()
                } else {
                    miniPlayer.hide()
                }
            }
            .store(in: &cancellables)

        state.$playbackState
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { playbackState in
                miniPlayer.refreshLayout()
                switch playbackState {
                case .preparing, .playing, .paused:
                    escapeMonitor.install()
                default:
                    escapeMonitor.remove()
                }
            }
            .store(in: &cancellables)

        state.$readingError
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { _ in
                miniPlayer.refreshLayout()
            }
            .store(in: &cancellables)
    }
}
