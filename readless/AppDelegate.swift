import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = ReadlessAppState()
    private let hotKeyStore = HotKeyConfigurationStore()
    private var menuBarController: MenuBarController?
    private var mainWindowController: MainWindowController?
    private var miniPlayerPanelController: MiniPlayerPanelController?
    private var onboardingWindowController: OnboardingWindowController?
    private var permissionController:
        AccessibilityPermissionController?
    private var voiceServiceSettings: VoiceServiceSettingsStore?
    private var credentialStore: LocalCredentialStore?
    private var voiceServiceSaver: VoiceServiceSaveCoordinator?
    private var readingCoordinator: ReadingCoordinator?
    private var hotKeyController: GlobalHotKeyController?
    private var clipboardHotKeyController: GlobalHotKeyController?
    private var escapeKeyMonitor: EscapeKeyMonitor?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !RuntimeEnvironment.isRunningInXcodePreview else {
            return
        }

        NSApplication.shared.setActivationPolicy(.accessory)

        let permissionController =
            AccessibilityPermissionController()
        let appState = state
        let voiceServiceSettings = VoiceServiceSettingsStore()
        let credentialStore = LocalCredentialStore()
        let recentReadingStore = LocalRecentReadingStore()
        state.replaceRecentReadings(
            (try? recentReadingStore.load()) ?? []
        )
        let voiceServiceSaver = VoiceServiceSaveCoordinator(
            settings: voiceServiceSettings,
            credentials: credentialStore
        )
        let speechEngine = CloudSpeechEngine(
            settings: voiceServiceSettings,
            credentials: credentialStore
        )
        let coordinator = ReadingCoordinator(
            state: state,
            permission: permissionController,
            selectionReader: AccessibilitySelectionReader(),
            clipboardReader: SystemClipboardReader(),
            voiceServiceReadiness: StoredVoiceServiceReadiness(
                settings: voiceServiceSettings,
                credentials: credentialStore
            ),
            sanitizer: DefaultTextSanitizer(),
            sentenceLocator: DefaultSentenceLocator(),
            speech: speechEngine,
            history: recentReadingStore
        )
        let hotKeyController = GlobalHotKeyController(identifier: 1) {
            coordinator.handleReadShortcut()
        }
        let clipboardHotKeyController = GlobalHotKeyController(identifier: 2) {
            coordinator.readClipboard()
        }
        let escapeKeyMonitor = EscapeKeyMonitor {
            coordinator.stop()
        }

        self.permissionController = permissionController
        self.voiceServiceSettings = voiceServiceSettings
        self.credentialStore = credentialStore
        self.voiceServiceSaver = voiceServiceSaver
        readingCoordinator = coordinator
        self.hotKeyController = hotKeyController
        self.clipboardHotKeyController = clipboardHotKeyController
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
            updateClipboardHotKey: { [weak self] configuration in
                self?.updateClipboardHotKey(configuration)
            },
            setRate: {
                coordinator.setRate($0)
            },
            seekPlayback: {
                coordinator.seek(to: $0)
            },
            openCurrentPlayback: { [weak self] in
                self?.showMainWindow(section: .currentPlayback)
            },
            voiceServiceProfiles: {
                voiceServiceSettings.profiles
            },
            hasVoiceServiceCredential: { slot in
                credentialStore.hasCredential(for: slot)
            },
            selectDoubaoVersion: { version in
                voiceServiceSettings.selectDoubaoVersion(version)
            },
            saveVoiceService: { configuration, credential in
                let result = voiceServiceSaver.save(
                    configuration: configuration,
                    credential: credential
                )
                if result == nil,
                   appState.isOnboardingVisible,
                   appState.onboardingStep == .configuration {
                    appState.advanceOnboarding(after: .configurationSaved)
                }
                return result
            },
            readTestSpeech: {
                coordinator.readTestSpeech()
            },
            requestOnboardingAccessibility: {
                permissionController.requestAccessPrompt()
            },
            confirmOnboardingAccessibility: { [weak self] in
                self?.confirmOnboardingAccessibility() ?? false
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
        let onboardingWindowController = OnboardingWindowController(
            state: state,
            actions: actions
        )

        self.mainWindowController = mainWindowController
        self.miniPlayerPanelController = miniPlayerPanelController
        self.onboardingWindowController = onboardingWindowController
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
            escapeMonitor: escapeKeyMonitor,
            onboarding: onboardingWindowController
        )
        registerSavedHotKeys()
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

    private func registerSavedHotKeys() {
        let configuration = hotKeyStore.load()
        state.hotKeyDisplayName = configuration.displayName
        if case .failure(let error) =
            hotKeyController?.register(configuration) {
            state.showFailure(error)
        }

        let clipboardConfiguration = hotKeyStore.loadClipboard()
        state.clipboardHotKeyDisplayName = clipboardConfiguration.displayName
        if case .failure(let error) =
            clipboardHotKeyController?.register(clipboardConfiguration) {
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

    private func updateClipboardHotKey(
        _ candidate: HotKeyConfiguration
    ) {
        guard let clipboardHotKeyController else {
            return
        }
        let previous = hotKeyStore.loadClipboard()
        switch clipboardHotKeyController.register(candidate) {
        case .success:
            hotKeyStore.saveClipboard(candidate)
            state.clipboardHotKeyDisplayName = candidate.displayName
            if state.readingError == .hotKeyConflict {
                state.dismissReadingError()
            }
        case .failure:
            _ = clipboardHotKeyController.register(previous)
            state.clipboardHotKeyDisplayName = previous.displayName
            switch state.playbackState {
            case .preparing, .playing, .paused:
                state.showNonInterruptingError(.hotKeyConflict)
            default:
                state.showFailure(.hotKeyConflict)
            }
        }
    }

    private func confirmOnboardingAccessibility() -> Bool {
        guard let permissionController, permissionController.isTrusted else {
            return false
        }
        state.advanceOnboarding(after: .accessibilityGranted)
        return true
    }

    private func bindRuntimeSurfaces(
        miniPlayer: MiniPlayerPanelController,
        escapeMonitor: EscapeKeyMonitor,
        onboarding: OnboardingWindowController
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

        state.$isOnboardingVisible
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { isVisible in
                if isVisible {
                    onboarding.show()
                } else {
                    onboarding.hide()
                }
            }
            .store(in: &cancellables)

        state.$onboardingStep
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] step in
                if step == .completed {
                    self?.voiceServiceSettings?.setHasCompletedOnboarding(true)
                }
            }
            .store(in: &cancellables)
    }
}
