struct ReadlessActions {
    let togglePlayback: () -> Void
    let stopPlayback: () -> Void
    let readClipboard: () -> Void
    let requestAccessibility: () -> Void
    let dismissError: () -> Void
    let updateHotKey: (HotKeyConfiguration) -> Void
    let setRate: (Float) -> Void
    let seekPlayback: (Double) -> Void
    let openCurrentPlayback: () -> Void
}
