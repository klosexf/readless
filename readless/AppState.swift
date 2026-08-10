import Combine
import Foundation

enum PlaybackState: String, CaseIterable, Equatable, Sendable {
    case idle
    case preparing
    case playing
    case paused
    case failed
    case completed
}

extension PlaybackState {
    var displayName: String {
        switch self {
        case .idle:
            "待机"
        case .preparing:
            "正在准备"
        case .playing:
            "正在朗读"
        case .paused:
            "已暂停"
        case .failed:
            "需要处理"
        case .completed:
            "朗读完成"
        }
    }
}

extension ReadingError {
    var userMessage: String {
        switch self {
        case .accessibilityPermissionRequired:
            "需要辅助功能权限，才能在你按下快捷键时读取当前选区。"
        case .focusedApplicationUnavailable,
             .focusedElementUnavailable,
             .selectedTextUnsupported:
            "这个应用里取不到文字。请先复制需要朗读的内容，再点击“朗读剪贴板”。"
        case .emptySelection:
            "当前没有可朗读的选中文字。"
        case .clipboardEmpty:
            "剪贴板里没有可朗读文字。"
        case .hotKeyConflict:
            "快捷键已被占用，请设置新的快捷键。"
        case .speechUnavailable, .speechFailed:
            "系统语音暂时无法朗读，请重试。"
        case .voiceServiceNotConfigured:
            "请先完成语音服务配置，再开始朗读。"
        case .voiceServiceNetworkUnavailable:
            "连不上语音服务，请检查网络后重试。"
        case .voiceServiceCredentialInvalid:
            "语音服务凭证无效，请检查设置。"
        case .doubaoAPIKeyInvalid:
            "豆包 API Key 无效。请填写新版控制台“API Key 管理”中的 API Key，不要填写 Access Token。"
        case .voiceServiceQuotaExceeded:
            "语音服务额度已用尽，请在服务商控制台处理。"
        case .voiceServiceTimedOut:
            "语音服务响应超时，请重试。"
        case .voiceServiceResponseInvalid:
            "语音服务返回了无法播放的结果，请重试。"
        case .recentReadingsUnavailable:
            "最近朗读记录暂时无法保存，请稍后重试。"
        }
    }
}

enum ManagementSection: String, CaseIterable, Equatable, Sendable {
    case currentPlayback
    case voiceService
    case recentReadings
}

enum MaterialMode: String, CaseIterable, Equatable, Sendable {
    case automatic
    case liquidGlass
    case compatibility
}

enum ContextMenuAction: String, Equatable, Sendable {
    case togglePlayback
    case readClipboard
    case recentReadings
    case voiceServiceSettings
    case quit
}

struct ContextMenuItemDescriptor: Equatable, Sendable {
    let title: String
    let action: ContextMenuAction

    var playbackCommandTitle: String? {
        action == .togglePlayback ? title : nil
    }
}

final class ReadlessAppState: ObservableObject {
    @Published var playbackState: PlaybackState = .idle
    @Published var managementSection: ManagementSection = .currentPlayback
    @Published var isManagementWindowVisible = false
    @Published var isContextMenuVisible = false
    @Published var isMiniPlayerVisible = false
    @Published var isMiniPlayerExpanded = false
    @Published var showsCurrentSentence = true
    @Published var sourceApplication: String?
    @Published var currentSentence: String?
    var sentences: [SentenceRange] = []
    @Published var progress = 0.0
    @Published var materialMode: MaterialMode = .automatic
    @Published var readingError: ReadingError?
    @Published var hotKeyDisplayName = "⌥R"
    @Published var clipboardHotKeyDisplayName = "⌥⇧R"
    @Published var hotKeyIsRecording = false
    @Published var isOnboardingVisible = false
    @Published var onboardingStep: OnboardingStep = .configuration
    @Published private(set) var recentReadings: [RecentReading] = []

    var visibleCurrentSentence: String? {
        guard isMiniPlayerExpanded, showsCurrentSentence else {
            return nil
        }
        return currentSentence
    }

    var contextMenuItems: [ContextMenuItemDescriptor] {
        var items: [ContextMenuItemDescriptor] = []

        if playbackState == .playing {
            items.append(
                ContextMenuItemDescriptor(
                    title: "暂停朗读",
                    action: .togglePlayback
                )
            )
        } else if playbackState == .paused {
            items.append(
                ContextMenuItemDescriptor(
                    title: "继续朗读",
                    action: .togglePlayback
                )
            )
        }

        items.append(
            ContextMenuItemDescriptor(
                title: "朗读剪贴板",
                action: .readClipboard
            )
        )
        items.append(
            ContextMenuItemDescriptor(
                title: "最近朗读",
                action: .recentReadings
            )
        )
        items.append(
            ContextMenuItemDescriptor(
                title: "语音服务设置",
                action: .voiceServiceSettings
            )
        )
        items.append(
            ContextMenuItemDescriptor(
                title: "退出桌面听读助手",
                action: .quit
            )
        )
        return items
    }

    func showManagementWindow(
        section: ManagementSection = .currentPlayback
    ) {
        managementSection = section
        isManagementWindowVisible = true
        isContextMenuVisible = false
    }

    func closeManagementWindow() {
        isManagementWindowVisible = false
    }

    func showContextMenu() {
        isContextMenuVisible = true
        isManagementWindowVisible = false
    }

    func closeContextMenu() {
        isContextMenuVisible = false
    }

    func showOnboarding(at step: OnboardingStep = .configuration) {
        onboardingStep = step
        isOnboardingVisible = true
    }

    func advanceOnboarding(after event: OnboardingEvent) {
        switch (onboardingStep, event) {
        case (.configuration, .configurationSaved):
            onboardingStep = .testSpeech
        case (.testSpeech, .testSpeechSucceeded):
            onboardingStep = .accessibility
        case (.accessibility, .accessibilityGranted):
            onboardingStep = .practice
        case (.practice, .practicePlaybackStarted):
            onboardingStep = .completed
            isOnboardingVisible = false
        default:
            break
        }
    }

    func beginPlayback(
        sourceApplication: String,
        sentence: String
    ) {
        self.sourceApplication = sourceApplication
        let range = NSRange(
            location: 0,
            length: sentence.utf16.count
        )
        sentences = [SentenceRange(text: sentence, range: range)]
        currentSentence = sentence
        readingError = nil
        playbackState = .playing
        progress = 0
        isMiniPlayerVisible = true
        isMiniPlayerExpanded = false
    }

    func beginPlayback(sourceApplication: String) {
        self.sourceApplication = sourceApplication
        readingError = nil
        playbackState = .playing
        progress = 0
        updateCurrentSentence()
        isMiniPlayerVisible = true
        isMiniPlayerExpanded = false
    }

    func preparePlayback(
        sourceApplication: String,
        sentence: String
    ) {
        self.sourceApplication = sourceApplication
        let range = NSRange(
            location: 0,
            length: sentence.utf16.count
        )
        sentences = [SentenceRange(text: sentence, range: range)]
        currentSentence = sentence
        readingError = nil
        playbackState = .preparing
        progress = 0
        isMiniPlayerVisible = true
        isMiniPlayerExpanded = false
    }

    func preparePlayback(
        sourceApplication: String,
        sentences: [SentenceRange]
    ) {
        self.sourceApplication = sourceApplication
        self.sentences = sentences
        readingError = nil
        playbackState = .preparing
        progress = 0
        updateCurrentSentence()
        isMiniPlayerVisible = true
        isMiniPlayerExpanded = false
    }

    func showFailure(_ error: ReadingError) {
        readingError = error
        playbackState = .failed
        progress = 0
        isMiniPlayerVisible = true
        isMiniPlayerExpanded = false
    }

    func showNonInterruptingError(_ error: ReadingError) {
        readingError = error
        isMiniPlayerVisible = true
    }

    func dismissReadingError() {
        readingError = nil
        if playbackState == .failed {
            stopPlayback()
        }
    }

    func completePlayback() {
        readingError = nil
        playbackState = .completed
        progress = 1
        updateCurrentSentence()
        isMiniPlayerVisible = true
    }

    func restartCompletedPlayback(at progress: Double) {
        guard playbackState == .completed else {
            return
        }
        playbackState = .playing
        self.progress = min(max(progress, 0), 1)
        updateCurrentSentence()
        isMiniPlayerVisible = true
    }

    func updateProgress(_ progress: Double) {
        guard playbackState == .playing || playbackState == .paused else {
            return
        }
        self.progress = min(max(progress, 0), 1)
        updateCurrentSentence()
    }

    private func updateCurrentSentence() {
        guard !sentences.isEmpty else {
            currentSentence = nil
            return
        }
        let totalLength = sentences.last?.range.upperBound ?? 0
        guard totalLength > 0 else {
            currentSentence = sentences.first?.text
            return
        }
        let clampedProgress = min(max(progress, 0), 1)
        let targetOffset = Int(Double(totalLength) * clampedProgress)
        currentSentence = sentences.first {
            NSLocationInRange(targetOffset, $0.range)
        }?.text ?? sentences.last?.text
    }

    func togglePlayback() {
        switch playbackState {
        case .playing:
            playbackState = .paused
        case .paused:
            playbackState = .playing
        default:
            break
        }
    }

    func setMiniPlayerExpanded(_ expanded: Bool) {
        isMiniPlayerExpanded = expanded
    }

    func replaceRecentReadings(_ readings: [RecentReading]) {
        recentReadings = Array(readings.prefix(3))
    }

    func stopPlayback() {
        playbackState = .idle
        readingError = nil
        progress = 0
        isMiniPlayerVisible = false
        isMiniPlayerExpanded = false
        sourceApplication = nil
        currentSentence = nil
        sentences = []
    }
}
