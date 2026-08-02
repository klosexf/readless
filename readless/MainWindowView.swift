import SwiftUI

struct MainWindowView: View {
    @ObservedObject var state: ReadlessAppState
    let actions: ReadlessActions

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.5)
            detail
        }
        .frame(minWidth: 560, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
    }

    private var sidebar: some View {
        ProgressiveGlassContainer(
            mode: state.materialMode,
            role: .regular,
            cornerRadius: 0
        ) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(.white)
                        .background(Color.accentColor)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 9,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text("听读助手")
                            .font(.system(size: 12, weight: .semibold))
                        Text("管理与设置")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)

                VStack(spacing: 4) {
                    ForEach(ManagementSection.allCases, id: \.rawValue) {
                        section in
                        Button {
                            state.managementSection = section
                        } label: {
                            Label(section.title, systemImage: section.icon)
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .frame(height: 34)
                                .background(
                                    state.managementSection == section
                                        ? Color.white.opacity(0.72)
                                        : Color.clear
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 8,
                                        style: .continuous
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            state.managementSection == section
                                ? .isSelected
                                : []
                        )
                    }
                }

                Spacer()

                Text("仅支持 Mac · macOS 15+")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 10)
            .frame(width: 174)
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch state.managementSection {
        case .currentPlayback:
            CurrentPlaybackView(state: state, actions: actions)
        case .voiceService:
            VoiceServiceView(actions: actions)
        case .recentReadings:
            RecentReadingsView()
        }
    }
}

private struct CurrentPlaybackView: View {
    @ObservedObject var state: ReadlessAppState
    let actions: ReadlessActions

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("当前播放")
                        .font(.system(size: 25, weight: .semibold))
                    Text("选中文字后按 \(state.hotKeyDisplayName) 开始朗读。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(state.playbackState.displayName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.1))
                    .clipShape(Capsule())
            }

            Group {
                if let error = state.readingError {
                    errorCard(error)
                } else if state.playbackState == .idle {
                    idleCard
                } else {
                    playbackCard
                }
            }

            VStack(spacing: 12) {
                ShortcutRecorderView(
                    title: "选区朗读快捷键",
                    displayName: state.hotKeyDisplayName,
                    onRecorded: actions.updateHotKey,
                    onRestoreDefault: {
                        actions.updateHotKey(.defaultReadSelection)
                    }
                )

                ShortcutRecorderView(
                    title: "剪贴板朗读快捷键",
                    displayName: state.clipboardHotKeyDisplayName,
                    onRecorded: actions.updateClipboardHotKey,
                    onRestoreDefault: {
                        actions.updateClipboardHotKey(
                            .defaultReadClipboard
                        )
                    }
                )

                Text("选中文字后按选区快捷键；复制文字后按剪贴板快捷键。")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(Color.white.opacity(0.62))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )

            Spacer()
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idleCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.cursor")
                .font(.system(size: 24))
                .foregroundStyle(Color.accentColor)
            Text("等待选中文字")
                .font(.system(size: 13, weight: .semibold))
            Text("Readless 只会在你按下快捷键时读取当前选区。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Button("朗读剪贴板", action: actions.readClipboard)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .cardStyle()
    }

    private var playbackCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 11) {
                Image(systemName: "waveform")
                    .font(.system(size: 17))
                    .frame(width: 38, height: 38)
                    .foregroundStyle(.white)
                    .background(Color.accentColor)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 10,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        "来自 \(state.sourceApplication ?? "未知应用")"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    Text(state.playbackState.displayName)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if state.playbackState == .preparing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            ProgressView(value: state.progress)
                .tint(.accentColor)

            if state.showsCurrentSentence,
               let sentence = state.currentSentence {
                Text(sentence)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(11)
                    .background(Color.accentColor.opacity(0.07))
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 9,
                            style: .continuous
                        )
                    )
            }

            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    Button(action: actions.togglePlayback) {
                        PlaybackControlButton(tone: .graphite) {
                            if state.playbackState == .paused {
                                PlaybackPlayGlyph()
                            } else {
                                PlaybackPauseGlyph()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(
                        state.playbackState == .paused
                            ? "继续朗读"
                            : "暂停朗读"
                    )
                    .accessibilityLabel(
                        state.playbackState == .paused
                            ? "继续朗读"
                            : "暂停朗读"
                    )

                    Button(action: actions.stopPlayback) {
                        PlaybackControlButton(tone: .stop) {
                            PlaybackStopGlyph()
                        }
                    }
                    .buttonStyle(.plain)
                    .help("停止朗读")
                    .accessibilityLabel("停止朗读")
                }

                Spacer(minLength: 20)

                Toggle(
                    "显示当前朗读句子",
                    isOn: $state.showsCurrentSentence
                )
                .font(.system(size: 12, weight: .semibold))
                .toggleStyle(.switch)
            }
        }
        .padding(18)
        .cardStyle()
    }

    private func errorCard(_ error: ReadingError) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                "需要处理",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.orange)

            Text(error.userMessage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack {
                switch error {
                case .accessibilityPermissionRequired:
                    Button(
                        "授权辅助功能",
                        action: actions.requestAccessibility
                    )
                case .focusedApplicationUnavailable,
                     .focusedElementUnavailable,
                     .selectedTextUnsupported,
                     .emptySelection,
                     .clipboardEmpty:
                    Button(
                        "朗读剪贴板",
                        action: actions.readClipboard
                    )
                case .hotKeyConflict:
                    Text("请在下方录制新的快捷键。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                case .speechUnavailable,
                     .speechFailed,
                     .voiceServiceNotConfigured,
                     .voiceServiceNetworkUnavailable,
                     .voiceServiceCredentialInvalid,
                     .voiceServiceQuotaExceeded,
                     .voiceServiceTimedOut,
                     .voiceServiceResponseInvalid:
                    EmptyView()
                }

                Spacer()
                Button("关闭", action: actions.dismissError)
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .cardStyle()
    }

    private var statusColor: Color {
        switch state.playbackState {
        case .playing, .completed:
            .green
        case .preparing:
            .blue
        case .paused:
            .orange
        case .failed:
            .red
        case .idle:
            .secondary
        }
    }
}

private struct PlaybackControlButton<Glyph: View>: View {
    enum Tone {
        case graphite
        case stop
    }

    let tone: Tone
    @ViewBuilder let glyph: () -> Glyph

    var body: some View {
        glyph()
            .foregroundStyle(foregroundColor)
            .frame(width: 30, height: 30)
            .background(backgroundColor)
            .clipShape(Circle())
    }

    private var foregroundColor: Color {
        switch tone {
        case .graphite:
            Color.primary.opacity(0.82)
        case .stop:
            .red
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .graphite:
            Color.primary.opacity(0.08)
        case .stop:
            Color.red.opacity(0.1)
        }
    }
}

private struct PlaybackPauseGlyph: View {
    var body: some View {
        HStack(spacing: 3.5) {
            Capsule()
                .frame(width: 3.5, height: 14)
            Capsule()
                .frame(width: 3.5, height: 14)
        }
    }
}

private struct PlaybackPlayGlyph: View {
    var body: some View {
        Triangle()
            .frame(width: 12, height: 14)
            .offset(x: 1)
    }
}

private struct PlaybackStopGlyph: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .frame(width: 13, height: 13)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private extension View {
    func cardStyle() -> some View {
        background(Color.white.opacity(0.68))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )
    }
}

private struct VoiceServiceView: View {
    let actions: ReadlessActions

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("语音服务")
                    .font(.system(size: 25, weight: .semibold))
                Text("仅豆包与 OpenAI-compatible 已接入；凭据只写入 macOS 钥匙串。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            VoiceServiceEditor(actions: actions)
                .padding(18)
                .background(Color.white.opacity(0.68))
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )

            Spacer()
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct VoiceServiceEditor: View {
    let actions: ReadlessActions
    let showsTestButton: Bool

    @State private var provider: VoiceProviderKind = .doubao
    @State private var appID = ""
    @State private var cluster = "volcano_tts"
    @State private var voiceType = "zh_female_wanwanxiaohe_moon_bigtts"
    @State private var baseURL = ""
    @State private var model = ""
    @State private var voice = ""
    @State private var credential = ""
    @State private var hasSavedCredential = false
    @State private var error: VoiceServiceSaveError?
    @State private var didLoad = false

    init(actions: ReadlessActions, showsTestButton: Bool = true) {
        self.actions = actions
        self.showsTestButton = showsTestButton
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            serviceFormRow("服务商") {
                Picker("服务商", selection: $provider) {
                    Text("豆包（火山引擎）").tag(VoiceProviderKind.doubao)
                    Text("OpenAI-compatible").tag(VoiceProviderKind.openAICompatible)
                    Text("OpenAI · 即将支持").tag(VoiceProviderKind.openAI)
                    Text("阿里百炼 · 即将支持").tag(VoiceProviderKind.alibaba)
                }
                .labelsHidden()
            }

            if provider.isAvailable {
                providerFields
            } else {
                Label("该服务商即将支持，当前不能保存。", systemImage: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }

            if let error {
                Label(error.userMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }

            Label(
                "不会经过 Readless 的服务器。发起朗读时，文字会直接发送给你配置的服务商；凭据不会显示或写入偏好设置。",
                systemImage: "info.circle"
            )
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                if hasSavedCredential {
                    Label("凭据已保存", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green)
                }
                Spacer()
                if showsTestButton {
                    Button("播放内置测试句", action: actions.readTestSpeech)
                        .disabled(!hasSavedCredential || !provider.isAvailable)
                }
                Button("保存", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(!provider.isAvailable)
            }
        }
        .onAppear(perform: loadSavedConfiguration)
    }

    @ViewBuilder
    private var providerFields: some View {
        switch provider {
        case .doubao:
            labeledField("App ID", text: $appID, prompt: "火山引擎 App ID")
            credentialField
            labeledField("Cluster", text: $cluster, prompt: "例如 volcano_tts")
            labeledField("音色", text: $voiceType, prompt: "voice_type")
        case .openAICompatible:
            labeledField("Base URL", text: $baseURL, prompt: "https://example.com")
            credentialField
            labeledField("模型", text: $model, prompt: "例如 tts-1")
            labeledField("音色", text: $voice, prompt: "例如 nova")
        case .openAI, .alibaba:
            EmptyView()
        }
    }

    private var credentialField: some View {
        serviceFormRow(provider == .doubao ? "Access Token" : "API Key") {
            SecureField(
                hasSavedCredential ? "如需替换，请输入新的凭据" : "凭据保存在钥匙串",
                text: $credential
            )
            .textFieldStyle(.roundedBorder)
        }
    }

    private func labeledField(
        _ title: String,
        text: Binding<String>,
        prompt: String
    ) -> some View {
        serviceFormRow(title) {
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func serviceFormRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 92, alignment: .leading)

            content()
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func save() {
        let configuration: VoiceServiceConfiguration
        switch provider {
        case .doubao:
            configuration = .doubao(
                appID: appID,
                cluster: cluster,
                voiceType: voiceType
            )
        case .openAICompatible:
            configuration = .openAICompatible(
                baseURL: baseURL,
                model: model,
                voice: voice
            )
        case .openAI, .alibaba:
            error = .validation(.unavailable)
            return
        }

        error = actions.saveVoiceService(provider, configuration, credential)
        guard error == nil else {
            return
        }
        credential = ""
        hasSavedCredential = true
    }

    private func loadSavedConfiguration() {
        guard !didLoad else {
            return
        }
        didLoad = true
        guard let configuration = actions.savedVoiceServiceConfiguration() else {
            return
        }

        provider = configuration.provider
        hasSavedCredential = actions.hasVoiceServiceCredential(provider)
        switch configuration {
        case let .doubao(savedAppID, savedCluster, savedVoiceType):
            appID = savedAppID
            cluster = savedCluster
            voiceType = savedVoiceType
        case let .openAICompatible(savedBaseURL, savedModel, savedVoice):
            baseURL = savedBaseURL
            model = savedModel
            voice = savedVoice
        }
    }
}

private struct RecentReadingsView: View {
    private let readings = [
        ("真正好的工具，应该在需要时出现…", "Safari · 刚刚", "3:42"),
        ("产品的核心不在于功能数量…", "备忘录 · 21:07", "5:08"),
        ("Gatekeeper 对公开分发应用…", "预览 · 昨天", "2:16")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("最近朗读")
                    .font(.system(size: 25, weight: .semibold))
                Text("只保存摘要、来源与时间。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(readings, id: \.0) { reading in
                    HStack(spacing: 11) {
                        Image(systemName: "text.quote")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 30, height: 30)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 8,
                                    style: .continuous
                                )
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reading.0)
                                .font(.system(size: 10, weight: .medium))
                            Text(reading.1)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(reading.2)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.66))
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 10,
                            style: .continuous
                        )
                    )
                }
            }

            Spacer()
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension ManagementSection {
    var title: String {
        switch self {
        case .currentPlayback: "当前播放"
        case .voiceService: "语音服务"
        case .recentReadings: "最近朗读"
        }
    }

    var icon: String {
        switch self {
        case .currentPlayback: "play.fill"
        case .voiceService: "sparkles"
        case .recentReadings: "clock"
        }
    }
}

struct MainWindowView_Previews: PreviewProvider {
    static var previews: some View {
        MainWindowView(
            state: PreviewFixtures.playingState(),
            actions: PreviewFixtures.actions
        )
        .frame(width: 620, height: 520)
        .previewDisplayName("当前播放")
    }
}
