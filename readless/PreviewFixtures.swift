import Foundation

@MainActor
enum PreviewFixtures {
    static var actions: ReadlessActions {
        ReadlessActions(
            togglePlayback: {},
            stopPlayback: {},
            readClipboard: {},
            requestAccessibility: {},
            dismissError: {},
            updateHotKey: { _ in },
            setRate: { _ in },
            seekPlayback: { _ in },
            openCurrentPlayback: {},
            savedVoiceServiceConfiguration: { nil },
            hasVoiceServiceCredential: { _ in false },
            saveVoiceService: { _, _, _ in nil },
            readTestSpeech: {},
            requestOnboardingAccessibility: {},
            confirmOnboardingAccessibility: { false }
        )
    }

    static func playingState(
        expanded: Bool = false
    ) -> ReadlessAppState {
        let state = ReadlessAppState()
        state.beginPlayback(
            sourceApplication: "Safari",
            sentence: "真正好的工具，应该在需要时出现，在不需要时安静地退到背景。"
        )
        state.progress = 0.42
        state.setMiniPlayerExpanded(expanded)
        return state
    }

    static func errorState(
        _ error: ReadingError = .accessibilityPermissionRequired
    ) -> ReadlessAppState {
        let state = ReadlessAppState()
        state.showFailure(error)
        return state
    }
}
