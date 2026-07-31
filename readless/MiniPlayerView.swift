import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var state: ReadlessAppState
    let actions: ReadlessActions
    let toggleExpanded: () -> Void

    @State private var speed = "1.0×"

    var body: some View {
        ProgressiveGlassContainer(
            mode: state.materialMode,
            role: .clear,
            cornerRadius: 16
        ) {
            Group {
                if let error = state.readingError {
                    errorContent(error)
                } else {
                    playbackContent
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(Color.black.opacity(0.58))
        }
        .padding(1)
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
                    ProgressView(value: state.progress)
                        .progressViewStyle(.linear)
                        .tint(.white)
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
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(error.userMessage)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            switch error {
            case .accessibilityPermissionRequired:
                Button(
                    "授权",
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
                Button(
                    "设置快捷键",
                    action: actions.openCurrentPlayback
                )
            case .speechUnavailable, .speechFailed:
                EmptyView()
            }

            Button(action: actions.dismissError) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭提示")
        }
        .buttonStyle(.bordered)
    }
}
