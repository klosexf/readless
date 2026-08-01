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
