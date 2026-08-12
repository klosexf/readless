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
                    Image("SidebarAppIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)

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
            RecentReadingsView(state: state)
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
                     .doubaoAPIKeyInvalid,
                     .voiceServiceQuotaExceeded,
                     .voiceServiceTimedOut,
                     .voiceServiceResponseInvalid,
                     .recentReadingsUnavailable:
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
                Text("仅豆包与 OpenAI-compatible 已接入；凭据只保存在本机 Readless 应用数据中。")
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
    @State private var doubaoVersion: DoubaoAPIVersion = .v3
    @State private var appID = ""
    @State private var cluster = "volcano_tts"
    @State private var voiceType = "zh_female_wanwanxiaohe_moon_bigtts"
    @State private var resourceID = "seed-tts-2.0"
    @State private var speaker = "zh_female_vv_uranus_bigtts"
    @State private var baseURL = ""
    @State private var model = ""
    @State private var voice = ""
    @State private var credential = ""
    @State private var savedCredentialSlots: Set<VoiceCredentialSlot> = []
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
                "不会经过 Readless 的服务器。文字会直接发送给你配置的服务商；凭据仅保存在这台 Mac 的 Readless 应用数据中。",
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
        .onChange(of: provider) { _, provider in
            if provider == .doubao {
                actions.selectDoubaoVersion(doubaoVersion)
            }
        }
        .onChange(of: doubaoVersion) { _, version in
            if provider == .doubao {
                actions.selectDoubaoVersion(version)
            }
        }
    }

    @ViewBuilder
    private var providerFields: some View {
        switch provider {
        case .doubao:
            serviceFormRow("接口版本") {
                Picker("接口版本", selection: $doubaoVersion) {
                    Text("V3（推荐）").tag(DoubaoAPIVersion.v3)
                    Text("V1（兼容）").tag(DoubaoAPIVersion.v1)
                }
                .labelsHidden()
            }
            switch doubaoVersion {
            case .v3:
                credentialField
                labeledField(
                    "资源 ID",
                    text: $resourceID,
                    prompt: "例如 seed-tts-2.0"
                )
                labeledField("音色 ID", text: $speaker, prompt: "speaker")
            case .v1:
                labeledField("App ID", text: $appID, prompt: "火山引擎 App ID")
                credentialField
                labeledField("Cluster", text: $cluster, prompt: "例如 volcano_tts")
                labeledField("音色", text: $voiceType, prompt: "voice_type")
            }
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
        serviceFormRow(credentialLabel) {
            SecureField(
                hasSavedCredential ? "如需替换，请输入新的凭据" : "凭据仅保存在这台 Mac",
                text: $credential
            )
            .textFieldStyle(.roundedBorder)
        }
    }

    private var credentialLabel: String {
        switch provider {
        case .doubao:
            doubaoVersion == .v3 ? "API Key" : "Access Token"
        case .openAICompatible:
            "API Key"
        case .openAI, .alibaba:
            "凭据"
        }
    }

    private var currentCredentialSlot: VoiceCredentialSlot? {
        switch provider {
        case .doubao:
            doubaoVersion == .v3 ? .doubaoV3 : .doubaoV1
        case .openAICompatible:
            .openAICompatible
        case .openAI, .alibaba:
            nil
        }
    }

    private var hasSavedCredential: Bool {
        guard let currentCredentialSlot else {
            return false
        }
        return savedCredentialSlots.contains(currentCredentialSlot)
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
        error = nil
        let configuration: VoiceServiceConfiguration
        switch provider {
        case .doubao:
            switch doubaoVersion {
            case .v3:
                configuration = .doubaoV3(
                    resourceID: resourceID,
                    speaker: speaker
                )
            case .v1:
                configuration = .doubao(
                    appID: appID,
                    cluster: cluster,
                    voiceType: voiceType
                )
            }
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

        error = actions.saveVoiceService(configuration, credential)
        guard error == nil else {
            return
        }
        if actions.hasVoiceServiceCredential(configuration.credentialSlot) {
            savedCredentialSlots.insert(configuration.credentialSlot)
        } else {
            savedCredentialSlots.remove(configuration.credentialSlot)
        }
    }

    private func loadSavedConfiguration() {
        guard !didLoad else {
            return
        }
        didLoad = true
        let profiles = actions.voiceServiceProfiles()
        provider = profiles.activeProvider
        doubaoVersion = profiles.activeDoubaoVersion
        if let configuration = profiles.doubaoV1,
           case let .doubao(savedAppID, savedCluster, savedVoiceType) = configuration {
            appID = savedAppID
            cluster = savedCluster
            voiceType = savedVoiceType
        }
        if let configuration = profiles.doubaoV3,
           case let .doubaoV3(savedResourceID, savedSpeaker) = configuration {
            resourceID = savedResourceID
            speaker = savedSpeaker
        }
        if let configuration = profiles.openAICompatible,
           case let .openAICompatible(savedBaseURL, savedModel, savedVoice) = configuration {
            baseURL = savedBaseURL
            model = savedModel
            voice = savedVoice
        }
        for slot in VoiceCredentialSlot.allCases where actions.hasVoiceServiceCredential(slot) {
            savedCredentialSlots.insert(slot)
        }
    }
}

private struct RecentReadingsView: View {
    @ObservedObject var state: ReadlessAppState
    @State private var expandedReadingIDs = Set<RecentReading.ID>()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("最近朗读")
                    .font(.system(size: 25, weight: .semibold))
                Text("完整正文仅保存在这台 Mac 上，最多保留三条。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if state.recentReadings.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                    Text("还没有最近朗读记录")
                        .font(.system(size: 12, weight: .medium))
                    Text("开始一次选区或剪贴板朗读后，记录会显示在这里。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .cardStyle()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(state.recentReadings) { reading in
                            let presentation = RecentReadingTextPresentation(
                                text: reading.text
                            )
                            let isExpanded = expandedReadingIDs.contains(reading.id)
                            HStack(alignment: .top, spacing: 11) {
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
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(
                                        isExpanded
                                            ? presentation.fullText
                                            : presentation.collapsedText
                                    )
                                        .font(.system(size: 11, weight: .medium))
                                        .fixedSize(
                                            horizontal: false,
                                            vertical: true
                                        )
                                    if presentation.isCollapsible {
                                        Button(isExpanded ? "收起" : "查看全部") {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                if isExpanded {
                                                    expandedReadingIDs.remove(reading.id)
                                                } else {
                                                    expandedReadingIDs.insert(reading.id)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.top, 1)
                                    }
                                    Text(
                                        "\(reading.sourceApplication) · \(reading.startedAt.formatted(date: .abbreviated, time: .shortened))"
                                    )
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.66))
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 10,
                                    style: .continuous
                                )
                            )
                            .animation(
                                .easeInOut(duration: 0.2),
                                value: expandedReadingIDs.contains(reading.id)
                            )
                        }
                    }
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
