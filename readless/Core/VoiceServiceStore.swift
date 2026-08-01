import Foundation

@MainActor
protocol VoiceServiceReadinessChecking {
    var isReadyForSpeech: Bool { get }
}

@MainActor
final class AlwaysReadyVoiceServiceReadiness:
    VoiceServiceReadinessChecking
{
    var isReadyForSpeech: Bool {
        true
    }
}
