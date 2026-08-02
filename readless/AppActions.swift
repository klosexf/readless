struct ReadlessActions {
    let togglePlayback: () -> Void
    let stopPlayback: () -> Void
    let readClipboard: () -> Void
    let requestAccessibility: () -> Void
    let dismissError: () -> Void
    let updateHotKey: (HotKeyConfiguration) -> Void
    let updateClipboardHotKey: (HotKeyConfiguration) -> Void
    let setRate: (Float) -> Void
    let seekPlayback: (Double) -> Void
    let openCurrentPlayback: () -> Void
    let savedVoiceServiceConfiguration: () -> VoiceServiceConfiguration?
    let hasVoiceServiceCredential: (VoiceProviderKind) -> Bool
    let saveVoiceService: (
        VoiceProviderKind,
        VoiceServiceConfiguration,
        String
    ) -> VoiceServiceSaveError?
    let readTestSpeech: () -> Void
    let requestOnboardingAccessibility: () -> Void
    let confirmOnboardingAccessibility: () -> Bool
}
