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

enum DoubaoAPIVersion: String, Codable, CaseIterable, Sendable {
    case v3
    case v1
}

enum VoiceCredentialSlot: String, Codable, CaseIterable, Sendable {
    case doubaoLegacy = "doubao"
    case doubaoV1 = "doubao-v1"
    case doubaoV3 = "doubao-v3"
    case openAICompatible
}

enum VoiceServiceValidationError: Equatable, Sendable {
    case appIDRequired
    case clusterRequired
    case resourceIDRequired
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
        case .validation(.resourceIDRequired):
            "请填写资源 ID。"
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
    case doubaoV3(resourceID: String, speaker: String)
    case openAICompatible(baseURL: String, model: String, voice: String)

    var provider: VoiceProviderKind {
        switch self {
        case .doubao, .doubaoV3:
            .doubao
        case .openAICompatible:
            .openAICompatible
        }
    }

    var credentialSlot: VoiceCredentialSlot {
        switch self {
        case .doubao:
            .doubaoV1
        case .doubaoV3:
            .doubaoV3
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
        case let .doubaoV3(resourceID, speaker):
            if resourceID.trimmed.isEmpty {
                return .resourceIDRequired
            }
            if speaker.trimmed.isEmpty {
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

struct VoiceServiceProfiles: Codable, Equatable, Sendable {
    var activeProvider: VoiceProviderKind
    var activeDoubaoVersion: DoubaoAPIVersion
    var doubaoV1: VoiceServiceConfiguration?
    var doubaoV3: VoiceServiceConfiguration?
    var openAICompatible: VoiceServiceConfiguration?

    init(
        activeProvider: VoiceProviderKind = .doubao,
        activeDoubaoVersion: DoubaoAPIVersion = .v3,
        doubaoV1: VoiceServiceConfiguration? = nil,
        doubaoV3: VoiceServiceConfiguration? = nil,
        openAICompatible: VoiceServiceConfiguration? = nil
    ) {
        self.activeProvider = activeProvider
        self.activeDoubaoVersion = activeDoubaoVersion
        self.doubaoV1 = doubaoV1
        self.doubaoV3 = doubaoV3
        self.openAICompatible = openAICompatible
    }

    static func migrated(from configuration: VoiceServiceConfiguration) -> Self {
        switch configuration {
        case .doubao:
            VoiceServiceProfiles(
                activeProvider: .doubao,
                activeDoubaoVersion: .v1,
                doubaoV1: configuration
            )
        case .doubaoV3:
            VoiceServiceProfiles(
                activeProvider: .doubao,
                activeDoubaoVersion: .v3,
                doubaoV3: configuration
            )
        case .openAICompatible:
            VoiceServiceProfiles(
                activeProvider: .openAICompatible,
                openAICompatible: configuration
            )
        }
    }

    var activeConfiguration: VoiceServiceConfiguration? {
        switch activeProvider {
        case .doubao:
            switch activeDoubaoVersion {
            case .v1:
                doubaoV1
            case .v3:
                doubaoV3
            }
        case .openAICompatible:
            openAICompatible
        case .openAI, .alibaba:
            nil
        }
    }

    mutating func selectDoubaoVersion(_ version: DoubaoAPIVersion) {
        activeProvider = .doubao
        activeDoubaoVersion = version
    }

    mutating func save(_ configuration: VoiceServiceConfiguration) {
        switch configuration {
        case .doubao:
            doubaoV1 = configuration
            selectDoubaoVersion(.v1)
        case .doubaoV3:
            doubaoV3 = configuration
            selectDoubaoVersion(.v3)
        case .openAICompatible:
            openAICompatible = configuration
            activeProvider = .openAICompatible
        }
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
