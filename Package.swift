// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ReadlessCoreTests",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "ReadlessCore", targets: ["ReadlessCore"])
    ],
    targets: [
        .target(
            name: "ReadlessCore",
            path: "readless",
            exclude: [
                "AppDelegate.swift",
                "AppActions.swift",
                "Assets.xcassets",
                "ContentView.swift",
                "Item.swift",
                "MainWindowController.swift",
                "MainWindowView.swift",
                "OnboardingWindowController.swift",
                "OnboardingView.swift",
                "MenuBarController.swift",
                "MiniPlayerPanelController.swift",
                "MiniPlayerView.swift",
                "PreviewFixtures.swift",
                "ProgressiveGlass.swift",
                "ShortcutRecorderView.swift",
                "System",
                "readlessApp.swift"
            ],
            sources: [
                "AppState.swift",
                "Core/ReadingModels.swift",
                "Core/VoiceServiceModels.swift",
                "Core/VoiceServiceStore.swift",
                "Core/CloudSpeechRequests.swift",
                "Core/TextSanitizer.swift",
                "Core/HotKeyConfiguration.swift",
                "Core/ReadingCoordinator.swift",
                "Core/RuntimeEnvironment.swift"
            ]
        ),
        .testTarget(
            name: "ReadlessCoreTests",
            dependencies: ["ReadlessCore"],
            path: "Tests/ReadlessCoreTests"
        )
    ]
)
