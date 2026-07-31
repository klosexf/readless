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
            VoiceServiceView()
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
                    displayName: state.hotKeyDisplayName,
                    onRecorded: actions.updateHotKey,
                    onRestoreDefault: {
                        actions.updateHotKey(.defaultReadSelection)
                    }
                )

                Text("若快捷键与输入法或常用应用冲突，可以在这里重新录制。")
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
                } else if state.playbackState == .playing
                            || state.playbackState == .paused {
                    Button(
                        state.playbackState == .paused ? "继续" : "暂停",
                        action: actions.togglePlayback
                    )
                    .buttonStyle(.bordered)
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

            HStack {
                Button(
                    "停止",
                    role: .destructive,
                    action: actions.stopPlayback
                )
                Spacer()
                Toggle(
                    "显示当前朗读句子",
                    isOn: $state.showsCurrentSentence
                )
                .font(.system(size: 10, weight: .medium))
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
                .font(.system(size: 10))
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
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                case .speechUnavailable, .speechFailed:
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
    @State private var provider = "豆包（火山引擎）"
    @State private var credential = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("语音服务")
                    .font(.system(size: 25, weight: .semibold))
                Text("字段随服务商自动变化。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                LabeledContent("服务商") {
                    Picker("", selection: $provider) {
                        Text("OpenAI").tag("OpenAI")
                        Text("豆包（火山引擎）").tag("豆包（火山引擎）")
                        Text("阿里百炼").tag("阿里百炼")
                        Text("OpenAI-compatible")
                            .tag("OpenAI-compatible")
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                LabeledContent("Access Token") {
                    SecureField("凭证保存在钥匙串", text: $credential)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                LabeledContent("音色") {
                    Picker("", selection: .constant("温和女声")) {
                        Text("温和女声").tag("温和女声")
                        Text("清朗男声").tag("清朗男声")
                        Text("沉稳旁白").tag("沉稳旁白")
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                Text("不上传到本项目服务器；你选择朗读的文字会发送给你配置的语音服务商。凭证只保存在 macOS 钥匙串。")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(11)
                    .background(.green.opacity(0.07))
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 9,
                            style: .continuous
                        )
                    )

                HStack {
                    Spacer()
                    Button("播放内置测试句") {}
                    Button("保存") {}
                        .buttonStyle(.borderedProminent)
                }
            }
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
