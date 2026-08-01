# Cloud Voice and Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add secure, configurable Doubao and OpenAI-compatible cloud speech plus a four-step onboarding flow that gates Accessibility permission until speech is verified.

**Architecture:** Provider-independent configuration, validation, onboarding state, error mapping, and coordinator gating live in `Core/` so SwiftPM tests cover every decision. Keychain access, HTTP/WebSocket transport, audio playback, and SwiftUI/AppKit surfaces remain in `System/` and view files. The project’s synchronized source root automatically includes new app files; no `.xcodeproj` edit is required.

**Tech Stack:** Swift 6, SwiftUI, Combine, Security Keychain Services, Foundation URLSession, AVFoundation, XCTest, macOS 15.

---

## File map

- Create `readless/Core/VoiceServiceModels.swift`: provider catalog, non-secret configuration, validation, cloud errors, onboarding state.
- Create `readless/Core/VoiceServiceStore.swift`: Core protocols and readiness decisions.
- Create `readless/System/KeychainCredentialStore.swift` and `VoiceServiceSettingsStore.swift`: secure secret storage and versioned non-secret preferences.
- Create `readless/System/OpenAICompatibleSpeechProvider.swift`, `DoubaoSpeechProvider.swift`, and `CloudSpeechEngine.swift`: provider transport and AVAudioPlayer playback.
- Create `readless/OnboardingWindowController.swift` and `OnboardingView.swift`: four-step onboarding.
- Modify `Package.swift`, `ReadingModels.swift`, `ReadingCoordinator.swift`, `AppState.swift`, `AppActions.swift`, `AppDelegate.swift`, and `MainWindowView.swift`.
- Create tests under `Tests/ReadlessCoreTests/`; update local-only `progress.md` with evidence.

### Task 1: Model provider configuration and onboarding state

**Files:**
- Create: `readless/Core/VoiceServiceModels.swift`
- Modify: `readless/Core/ReadingModels.swift`, `Package.swift`
- Create: `Tests/ReadlessCoreTests/VoiceServiceModelsTests.swift`

- [ ] **Step 1: Write failing configuration tests.**

```swift
func testDoubaoRequiresAppIDClusterAndVoice() {
    let value = VoiceServiceConfiguration.doubao(
        appID: "", cluster: "", voiceType: ""
    )
    XCTAssertEqual(value.validationError, .appIDRequired)
}

func testCompatibleServiceRequiresHTTPSURLModelAndVoice() {
    let value = VoiceServiceConfiguration.openAICompatible(
        baseURL: "http://tts.example", model: "", voice: ""
    )
    XCTAssertEqual(value.validationError, .secureBaseURLRequired)
}

func testOpenAIAndAlibabaAreUnavailableCatalogEntries() {
    XCTAssertFalse(VoiceProviderKind.openAI.isAvailable)
    XCTAssertFalse(VoiceProviderKind.alibaba.isAvailable)
}
```

- [ ] **Step 2: Verify RED.**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter VoiceServiceModelsTests
```

Expected: compile failure because configuration types are absent.

- [ ] **Step 3: Implement the minimal models.**

```swift
enum VoiceProviderKind: String, Codable, CaseIterable, Sendable {
    case doubao, openAICompatible, openAI, alibaba

    var isAvailable: Bool {
        self == .doubao || self == .openAICompatible
    }
}
```

Create an exhaustive non-secret `VoiceServiceConfiguration` payload for Doubao and compatible services. Add configuration validation, `OnboardingStep` (`configuration`, `testSpeech`, `accessibility`, `practice`, `completed`), and the approved `ReadingError` cases for missing config, network, credential, quota, timeout, and invalid response. Never include secrets in a Codable value.

- [ ] **Step 4: Include the Core source in `Package.swift` and verify GREEN.**

Rerun Step 2; expected: all three tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Package.swift readless/Core/ReadingModels.swift readless/Core/VoiceServiceModels.swift Tests/ReadlessCoreTests/VoiceServiceModelsTests.swift
git commit -m "feat: model cloud voice configuration"
```

### Task 2: Prevent collection before configuration and guard onboarding order

**Files:**
- Create: `readless/Core/VoiceServiceStore.swift`
- Modify: `readless/Core/ReadingCoordinator.swift`, `readless/AppState.swift`, `Package.swift`
- Modify: `Tests/ReadlessCoreTests/ReadingCoordinatorTests.swift`, `Tests/ReadlessCoreTests/AppStateTests.swift`

- [ ] **Step 1: Write failing privacy and transition tests.**

```swift
func testUnconfiguredShortcutShowsConfigurationWithoutReadingSelection() {
    readiness.isReady = false
    coordinator.handleReadShortcut()

    XCTAssertEqual(selection.readCount, 0)
    XCTAssertTrue(state.isOnboardingVisible)
    XCTAssertEqual(state.onboardingStep, .configuration)
}

func testAccessibilityCannotAdvanceBeforeTestSpeechSuccess() {
    state.advanceOnboarding(after: .configurationSaved)
    state.advanceOnboarding(after: .accessibilityGranted)

    XCTAssertEqual(state.onboardingStep, .testSpeech)
}
```

- [ ] **Step 2: Verify RED.**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter 'ReadingCoordinatorTests|AppStateTests'
```

Expected: compile failure because readiness and onboarding API are absent.

- [ ] **Step 3: Implement readiness and strict transitions.**

Add:

```swift
@MainActor
protocol VoiceServiceReadinessChecking {
    var isReadyForSpeech: Bool { get }
}
```

Inject it into `ReadingCoordinator`. Its first shortcut guard must show onboarding at `.configuration` and return before checking permission or touching the selection reader. Add explicit state transition methods: configuration saved → test speech; only test success → accessibility; only confirmed grant → practice; only a playback start in practice → completed.

- [ ] **Step 4: Verify GREEN.**

Run the filtered command above, then:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test
```

Expected: all existing and new Core tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Package.swift readless/Core/VoiceServiceStore.swift readless/Core/ReadingCoordinator.swift readless/AppState.swift Tests/ReadlessCoreTests/ReadingCoordinatorTests.swift Tests/ReadlessCoreTests/AppStateTests.swift
git commit -m "feat: gate reading on configured cloud voice"
```

### Task 3: Securely persist configuration and credentials

**Files:**
- Create: `readless/System/KeychainCredentialStore.swift`, `readless/System/VoiceServiceSettingsStore.swift`
- Modify: `readless/Core/VoiceServiceStore.swift`
- Create: `Tests/ReadlessCoreTests/VoiceServiceStoreTests.swift`
- Modify: `Package.swift`

- [ ] **Step 1: Write failing store-contract tests.**

```swift
func testReadinessNeedsBothValidConfigurationAndCredential() {
    readiness.configuration = .doubao(
        appID: "id", cluster: "volcano_tts", voiceType: "voice"
    )
    readiness.hasCredential = false

    XCTAssertFalse(readiness.isReadyForSpeech)
}

func testConfigurationSerializationCannotContainCredential() throws {
    let data = try JSONEncoder().encode(
        VoiceServiceConfiguration.openAICompatible(
            baseURL: "https://tts.example", model: "tts", voice: "nova"
        )
    )
    XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("secret"))
}
```

- [ ] **Step 2: Verify RED.**

Run the `VoiceServiceStoreTests` filter; expected failure is missing readiness/store code.

- [ ] **Step 3: Implement stores.**

Use `SecItemUpdate`, then `SecItemAdd` only when `errSecItemNotFound`; identify items with a fixed service and per-provider account. Store only the encoded non-secret configuration and `hasCompletedOnboarding` under dedicated versioned `UserDefaults` keys. A secret is deleted only after the user explicitly clears/replaces that provider.

- [ ] **Step 4: Verify GREEN and compile the app.**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project readless.xcodeproj -scheme readless -configuration Debug -derivedDataPath /tmp/readless-cloud-voice-derived build CODE_SIGNING_ALLOWED=NO
```

Expected: Core tests pass and Keychain source compiles.

- [ ] **Step 5: Commit.**

```bash
git add Package.swift readless/Core/VoiceServiceStore.swift readless/System/KeychainCredentialStore.swift readless/System/VoiceServiceSettingsStore.swift Tests/ReadlessCoreTests/VoiceServiceStoreTests.swift
git commit -m "feat: persist cloud voice settings securely"
```

### Task 4: Implement provider calls and cloud audio playback

**Files:**
- Create: `readless/System/OpenAICompatibleSpeechProvider.swift`, `readless/System/DoubaoSpeechProvider.swift`, `readless/System/CloudSpeechEngine.swift`
- Modify: `readless/Core/ReadingModels.swift`, `readless/AppDelegate.swift`
- Create: `Tests/ReadlessCoreTests/CloudSpeechRequestTests.swift`
- Modify: `Package.swift`

- [ ] **Step 1: Write failing request/error tests.**

```swift
func testCompatibleRequestUsesSpeechPathAndAuthorization() throws {
    let request = try OpenAICompatibleRequestBuilder.make(
        configuration: configuration, apiKey: "secret", text: "测试"
    )

    XCTAssertEqual(request.url?.path, "/v1/audio/speech")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
}

func testUnauthorizedResponseMapsToCredentialError() {
    XCTAssertEqual(
        CloudSpeechErrorMapper.map(statusCode: 401),
        .voiceServiceCredentialInvalid
    )
}
```

- [ ] **Step 2: Verify RED.**

Run the `CloudSpeechRequestTests` filter. Expected: missing request builder and mapper.

- [ ] **Step 3: Implement the compatible provider.**

Build a `POST` to the normalized HTTPS base URL plus `/v1/audio/speech` with `Authorization: Bearer <key>`, JSON body `model`, `input`, `voice`, `response_format: mp3`, and a 15-second timeout. Map 401/403 to credential, 408/504 to timeout, 429 to quota, connectivity to network, 5xx and malformed audio to invalid-response. Never log raw bodies.

- [ ] **Step 4: Implement the Doubao provider.**

Use a fresh `URLSessionWebSocketTask` per synthesis against the official V1 one-way endpoint. Encode its documented binary request envelope with a UUID request ID, configured App ID/cluster/voice type, MP3 encoding, and selected speed; decode only documented audio/error frames. Map authentication, quota, timeout, invalid-voice, and unknown protocol errors to the stable Core errors; retain neither token nor source text after each request. Keep the codec confined to this provider so V3 can replace it without affecting other layers.

- [ ] **Step 5: Implement `CloudSpeechEngine`.**

Preserve the existing `SpeechEngine` contract. Feed provider MP3 data to `AVAudioPlayer`; emit start only when playback actually begins, progress as `currentTime / duration`, and exactly one terminal completion/failure callback per session. Pause, resume, stop, and seek must use the audio player and ignore stale provider callbacks. Replace `SystemSpeechEngine` with this engine only in `AppDelegate` production wiring.

- [ ] **Step 6: Verify GREEN.**

Run the Task 3 commands. Expected: request tests and Core suite pass; Xcode compiles the provider and AVFoundation sources.

- [ ] **Step 7: Commit.**

```bash
git add Package.swift readless/Core/ReadingModels.swift readless/System/OpenAICompatibleSpeechProvider.swift readless/System/DoubaoSpeechProvider.swift readless/System/CloudSpeechEngine.swift readless/AppDelegate.swift Tests/ReadlessCoreTests/CloudSpeechRequestTests.swift
git commit -m "feat: add cloud speech providers"
```

### Task 5: Build settings and onboarding UI

**Files:**
- Create: `readless/OnboardingWindowController.swift`, `readless/OnboardingView.swift`
- Modify: `readless/MainWindowView.swift`, `readless/AppActions.swift`, `readless/AppDelegate.swift`, `readless/AppState.swift`
- Modify: `Tests/ReadlessCoreTests/AppStateTests.swift`

- [ ] **Step 1: Add failing UI-state tests.**

Add assertions that unavailable providers cannot be saved, a failed test stays on `.testSpeech`, and a successful practice playback marks onboarding completed. Run `AppStateTests`; expected: missing state/actions.

- [ ] **Step 2: Replace the placeholder settings view.**

For Doubao show App ID, Access Token, Cluster, voice type; for compatible show Base URL, API Key, model, voice. Secrets stay in blank `SecureField` controls and are represented after saving only by “已保存”. OpenAI and 阿里 remain visible, disabled, and labelled “即将支持”. Wire save/test through `ReadlessActions`.

- [ ] **Step 3: Implement the four-step window.**

Configuration → fixed built-in test sentence → Accessibility permission → shortcut practice. Continue is disabled until the current predicate succeeds. Back never erases configuration. The test step uses the same provider/error mapping but never sends user-selected text. The practice step completes only on the coordinator’s first real playback start.

- [ ] **Step 4: Wire runtime presentation.**

Create a single onboarding controller in `AppDelegate`, bind `state.isOnboardingVisible`, inject the stores and cloud engine, and open the configuration step when readiness is false. Leave menu-bar accessory policy and global-hotkey registration unchanged.

- [ ] **Step 5: Verify UI compilation.**

Run the complete Core suite and Xcode command from Task 3. Expected: all tests pass and SwiftUI/AppKit compilation succeeds.

- [ ] **Step 6: Commit.**

```bash
git add readless/OnboardingWindowController.swift readless/OnboardingView.swift readless/MainWindowView.swift readless/AppActions.swift readless/AppDelegate.swift readless/AppState.swift Tests/ReadlessCoreTests/AppStateTests.swift
git commit -m "feat: add cloud voice onboarding"
```

### Task 6: Verify the complete flow and record evidence

**Files:**
- Modify: `progress.md`

- [ ] **Step 1: Run final automated checks.**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project readless.xcodeproj -scheme readless -configuration Debug -derivedDataPath /tmp/readless-cloud-voice-derived build CODE_SIGNING_ALLOWED=NO
git diff --check
```

Expected: tests and Debug build pass; no whitespace errors.

- [ ] **Step 2: Perform manual privacy and flow verification with user-owned credentials.**

1. Launch fresh with no setup, invoke shortcut, and confirm configuration opens without Accessibility request or selection read.
2. Test each supported provider with a fixed test sentence; cover valid credential, invalid credential, offline, quota, and timeout paths.
3. Confirm Accessibility is requested only after test success; deny, then grant it.
4. Select text in TextEdit and exercise play, pause, resume, seek, and stop.
5. Confirm no token, selection text, clipboard, or raw provider response is in logs/UserDefaults; reopen settings and confirm only “已保存” is shown.

- [ ] **Step 3: Record actual evidence in local-only `progress.md`.**

Include commands, result counts, build outcome, manual steps completed, and genuine blockers. Never include credentials, source text, raw request bodies, or response payloads.

- [ ] **Step 4: Commit evidence.**

```bash
git add progress.md
git commit -m "docs: record cloud voice verification"
```
