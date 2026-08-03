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
    let voiceServiceProfiles: () -> VoiceServiceProfiles
    let hasVoiceServiceCredential: (VoiceCredentialSlot) -> Bool
    let selectDoubaoVersion: (DoubaoAPIVersion) -> Void
    let saveVoiceService: (
        VoiceServiceConfiguration,
        String
    ) -> VoiceServiceSaveError?
    let readTestSpeech: () -> Void
    let requestOnboardingAccessibility: () -> Void
    let confirmOnboardingAccessibility: () -> Bool
}
