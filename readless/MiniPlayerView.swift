import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var state: ReadlessAppState
    let actions: ReadlessActions
    let toggleExpanded: () -> Void

    @State private var speed = "1.0×"
    @State private var displayedProgress = 0.0

    private var errorSurfaceShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    var body: some View {
        ProgressiveGlassContainer(
            mode: state.materialMode,
            role: .clear,
            cornerRadius: 18
        ) {
            Group {
                if let error = state.readingError {
                    errorContent(error)
                } else {
                    playbackContent
                }
            }
            .padding(.horizontal, state.readingError == nil ? 12 : 16)
            .padding(.vertical, state.readingError == nil ? 10 : 12)
            .foregroundStyle(.white)
            .background {
                errorSurfaceShape
                    .fill(Color.black.opacity(0.56))
            }
            .clipShape(errorSurfaceShape)
        }
        .padding(1)
        .onChange(of: state.progress) {
            displayedProgress = state.progress
        }
    }

    private var playbackContent: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button(action: actions.togglePlayback) {
                    Image(
                        systemName: state.playbackState == .paused
                            ? "play.fill"
                            : "pause.fill"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.white)
                    .background(.white.opacity(0.13))
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(state.playbackState == .preparing)
                .accessibilityLabel(
                    state.playbackState == .paused ? "继续" : "暂停"
                )

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(
                            "来自 \(state.sourceApplication ?? "未知应用")"
                        )
                        .font(.system(size: 10, weight: .semibold))
                        Spacer()
                        Text(state.playbackState.displayName)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $displayedProgress,
                        in: 0...1,
                        onEditingChanged: { isEditing in
                            if !isEditing {
                                actions.seekPlayback(displayedProgress)
                            }
                        }
                    )
                        .tint(.white)
                        .disabled(
                            state.playbackState != .playing
                                && state.playbackState != .completed
                        )
                        .accessibilityLabel("朗读进度")
                        .accessibilityValue(
                            "\(Int(displayedProgress * 100))%"
                        )
                }

                Picker("", selection: $speed) {
                    Text("1.0×").tag("1.0×")
                    Text("1.25×").tag("1.25×")
                    Text("1.5×").tag("1.5×")
                    Text("2.0×").tag("2.0×")
                    Text("3.0×").tag("3.0×")
                }
                .labelsHidden()
                .frame(width: 64)
                .onChange(of: speed) {
                    actions.setRate(Float(speed.dropLast()) ?? 1)
                }

                Button(action: toggleExpanded) {
                    Image(
                        systemName: state.isMiniPlayerExpanded
                            ? "chevron.down"
                            : "chevron.up"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    state.isMiniPlayerExpanded
                        ? "收起播放器"
                        : "展开播放器"
                )
            }

            if let sentence = state.visibleCurrentSentence {
                Divider().opacity(0.2)
                HStack(alignment: .top, spacing: 12) {
                    Text(sentence)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(2)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )

                    Button(
                        "停止",
                        role: .destructive,
                        action: actions.stopPlayback
                    )
                }
                .buttonStyle(.borderless)
                .font(.system(size: 9))
            }
        }
    }

    private func errorContent(_ error: ReadingError) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)

            Text(error.userMessage)
                .font(.system(size: 12, weight: .semibold))
                .lineSpacing(2)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            switch error {
            case .accessibilityPermissionRequired:
                Button(
                    "授权",
                    action: actions.requestAccessibility
                )
                .controlSize(.regular)
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
                Button(
                    "设置快捷键",
                    action: actions.openCurrentPlayback
                )
            case .speechUnavailable, .speechFailed:
                EmptyView()
            }

            Button(action: actions.dismissError) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭提示")
        }
        .buttonStyle(.bordered)
    }
}

struct MiniPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            MiniPlayerView(
                state: PreviewFixtures.playingState(),
                actions: PreviewFixtures.actions,
                toggleExpanded: {}
            )
            .frame(width: 580, height: 52)

            MiniPlayerView(
                state: PreviewFixtures.playingState(expanded: true),
                actions: PreviewFixtures.actions,
                toggleExpanded: {}
            )
            .frame(width: 620, height: 126)

            MiniPlayerView(
                state: PreviewFixtures.errorState(),
                actions: PreviewFixtures.actions,
                toggleExpanded: {}
            )
            .frame(width: 580, height: 82)
        }
        .padding(24)
        .frame(width: 680)
        .previewDisplayName("播放器状态")
    }
}
