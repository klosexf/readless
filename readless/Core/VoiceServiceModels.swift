import Foundation

enum VoiceProviderKind: String, Codable, CaseIterable, Sendable {
    case doubao
    case openAICompatible
    case openAI
    case alibaba

    var isAvailable: Bool {
        self == .doubao || self == .openAICompatible
    }
}

enum VoiceServiceValidationError: Equatable, Sendable {
    case appIDRequired
    case clusterRequired
    case voiceRequired
    case secureBaseURLRequired
    case modelRequired
    case unavailable
}

enum VoiceServiceSaveError: Equatable, Sendable {
    case validation(VoiceServiceValidationError)
    case credentialRequired
    case persistenceFailed

    var userMessage: String {
        switch self {
        case .validation(.appIDRequired):
            "请填写豆包 App ID。"
        case .validation(.clusterRequired):
            "请填写豆包 Cluster。"
        case .validation(.voiceRequired):
            "请填写音色。"
        case .validation(.secureBaseURLRequired):
            "兼容接口需要有效的 HTTPS Base URL。"
        case .validation(.modelRequired):
            "请填写模型名称。"
        case .validation(.unavailable):
            "该服务商即将支持，暂时不能保存。"
        case .credentialRequired:
            "请填写凭据。"
        case .persistenceFailed:
            "无法保存凭据到 macOS 钥匙串，请重试。"
        }
    }
}

enum VoiceServiceConfiguration: Codable, Equatable, Sendable {
    case doubao(appID: String, cluster: String, voiceType: String)
    case openAICompatible(baseURL: String, model: String, voice: String)

    var provider: VoiceProviderKind {
        switch self {
        case .doubao:
            .doubao
        case .openAICompatible:
            .openAICompatible
        }
    }

    var validationError: VoiceServiceValidationError? {
        switch self {
        case let .doubao(appID, cluster, voiceType):
            if appID.trimmed.isEmpty {
                return .appIDRequired
            }
            if cluster.trimmed.isEmpty {
                return .clusterRequired
            }
            if voiceType.trimmed.isEmpty {
                return .voiceRequired
            }
        case let .openAICompatible(baseURL, model, voice):
            guard let url = URL(string: baseURL.trimmed),
                  url.scheme == "https",
                  url.host != nil
            else {
                return .secureBaseURLRequired
            }
            if model.trimmed.isEmpty {
                return .modelRequired
            }
            if voice.trimmed.isEmpty {
                return .voiceRequired
            }
        }
        return nil
    }
}

enum VoiceServiceConfigurationValidator {
    static func saveError(
        for provider: VoiceProviderKind,
        configuration: VoiceServiceConfiguration,
        credential: String
    ) -> VoiceServiceSaveError? {
        guard provider.isAvailable else {
            return .validation(.unavailable)
        }
        guard configuration.provider == provider else {
            return .validation(.unavailable)
        }
        if let error = configuration.validationError {
            return .validation(error)
        }
        if credential.trimmed.isEmpty {
            return .credentialRequired
        }
        return nil
    }
}

enum OnboardingStep: Int, CaseIterable, Equatable, Sendable {
    case configuration
    case testSpeech
    case accessibility
    case practice
    case completed
}

enum OnboardingEvent: Equatable, Sendable {
    case configurationSaved
    case testSpeechSucceeded
    case accessibilityGranted
    case practicePlaybackStarted
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
