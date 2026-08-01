import SwiftUI

struct OnboardingView: View {
    @ObservedObject var state: ReadlessAppState
    let actions: ReadlessActions
    @State private var accessibilityMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            steps
            Divider().opacity(0.5)
            content
            Spacer(minLength: 0)
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.78))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 42, height: 42)
                .foregroundStyle(.white)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("准备好开始听读")
                    .font(.system(size: 22, weight: .semibold))
                Text("四步完成配置；每一步只在需要时请求相应权限。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var steps: some View {
        HStack(spacing: 7) {
            ForEach([OnboardingStep.configuration, .testSpeech, .accessibility, .practice], id: \.self) { step in
                VStack(spacing: 5) {
                    Text("\(step.rawValue + 1)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(stepColor(for: step))
                        .frame(width: 20, height: 20)
                        .background(stepColor(for: step).opacity(0.13))
                        .clipShape(Circle())
                    Text(step.title)
                        .font(.system(size: 9, weight: step == state.onboardingStep ? .semibold : .regular))
                        .foregroundStyle(step == state.onboardingStep ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.onboardingStep {
        case .configuration:
            VStack(alignment: .leading, spacing: 12) {
                Text("1. 选择并保存语音服务")
                    .font(.system(size: 14, weight: .semibold))
                Text("保存成功后，才会解锁内置试播。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                VoiceServiceEditor(actions: actions, showsTestButton: false)
            }
        case .testSpeech:
            stepCard(
                title: "2. 播放内置测试句",
                detail: "这一步只发送固定测试文本，不会读取屏幕选区或剪贴板。"
            ) {
                Button("播放内置测试句", action: actions.readTestSpeech)
                    .buttonStyle(.borderedProminent)
                if let error = state.readingError {
                    Text(error.userMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }
        case .accessibility:
            stepCard(
                title: "3. 授权辅助功能",
                detail: "授权后，Readless 才能在你按下快捷键时读取当前选中的文字。"
            ) {
                Button("打开系统设置") {
                    accessibilityMessage = nil
                    actions.requestOnboardingAccessibility()
                }
                .buttonStyle(.bordered)
                Button("我已授权，继续") {
                    if actions.confirmOnboardingAccessibility() {
                        accessibilityMessage = nil
                    } else {
                        accessibilityMessage = "尚未检测到辅助功能权限，请在系统设置中允许 Readless 后再继续。"
                    }
                }
                .buttonStyle(.borderedProminent)
                if let accessibilityMessage {
                    Text(accessibilityMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }
        case .practice:
            stepCard(
                title: "4. 用快捷键练习一次",
                detail: "在任意支持选区的应用中选中一段文字，然后按 \(state.hotKeyDisplayName)。首次实际朗读开始后，引导会自动完成。"
            ) {
                Label("等待一次真实朗读", systemImage: "keyboard")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        case .completed:
            EmptyView()
        }
    }

    private func stepCard<Content: View>(
        title: String,
        detail: String,
        @ViewBuilder actionsContent: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                actionsContent()
                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stepColor(for step: OnboardingStep) -> Color {
        if step.rawValue < state.onboardingStep.rawValue {
            return .green
        }
        return step == state.onboardingStep ? .accentColor : .secondary
    }
}

private extension OnboardingStep {
    var title: String {
        switch self {
        case .configuration: "配置"
        case .testSpeech: "试播"
        case .accessibility: "权限"
        case .practice: "练习"
        case .completed: "完成"
        }
    }
}
