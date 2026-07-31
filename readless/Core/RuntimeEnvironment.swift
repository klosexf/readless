import Foundation

enum RuntimeEnvironment {
    static var isRunningInXcodePreview: Bool {
        ProcessInfo.processInfo.environment[
            "XCODE_RUNNING_FOR_PREVIEWS"
        ] == "1"
    }
}
