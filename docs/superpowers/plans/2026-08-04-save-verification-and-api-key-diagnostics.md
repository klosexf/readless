# Save Verification and API Key Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Readless report local save success from durable read-back state and show a provider-specific, actionable error for an invalid Doubao V3 API Key.

**Architecture:** Extract local save orchestration from `AppDelegate` into a small `VoiceServiceSaveCoordinator` that owns validation, writes, and recovery-by-read-back. Keep generic HTTP credential mapping for OpenAI-compatible, while adding a Doubao-specific error path for V3 HTTP and protocol errors.

**Tech Stack:** Swift 6, SwiftUI/AppKit, Foundation `UserDefaults` and local JSON storage, XCTest, Swift Package Manager, Xcode/macOS code signing.

---

## File map

- Create `readless/Core/VoiceServiceSaveCoordinator.swift`: testable save orchestration and durable-state recovery.
- Create `Tests/ReadlessCoreTests/VoiceServiceSaveCoordinatorTests.swift`: normal, recoverable partial-error, and genuine failure cases.
- Modify `readless/Core/VoiceServiceStore.swift`: add the settings-saving protocol required by the coordinator.
- Modify `readless/System/VoiceServiceSettingsStore.swift`: conform the concrete store to the saving protocol.
- Modify `readless/AppDelegate.swift`: delegate saving to the coordinator and retain onboarding behavior.
- Modify `Package.swift`: compile the new coordinator in the SwiftPM core target.
- Modify `readless/Core/ReadingModels.swift`: add a Doubao-specific invalid API Key error.
- Modify `readless/Core/CloudSpeechRequests.swift`: preserve generic credential mapping and add Doubao-specific mapping.
- Modify `readless/System/DoubaoV3SpeechProvider.swift`: use the Doubao-specific HTTP status mapper.
- Modify `readless/AppState.swift`: expose the actionable Doubao API Key message.
- Modify `readless/MainWindowView.swift` and `readless/MiniPlayerView.swift`: handle the new exhaustive error case without adding new controls.
- Modify `Tests/ReadlessCoreTests/CloudSpeechRequestTests.swift`: verify generic and Doubao-specific mapping remain distinct.
- Modify `Tests/ReadlessCoreTests/DoubaoV3SpeechProviderSourceTests.swift`: require the provider-specific HTTP mapper.
- Modify `Tests/ReadlessCoreTests/AppStateTests.swift`: verify the exact actionable message.

### Task 1: Durable save coordinator

**Files:**
- Create: `Tests/ReadlessCoreTests/VoiceServiceSaveCoordinatorTests.swift`
- Create: `readless/Core/VoiceServiceSaveCoordinator.swift`
- Modify: `readless/Core/VoiceServiceStore.swift`
- Modify: `readless/System/VoiceServiceSettingsStore.swift`
- Modify: `Package.swift`

- [ ] **Step 1: Write the failing coordinator tests**

Create `Tests/ReadlessCoreTests/VoiceServiceSaveCoordinatorTests.swift` with real in-memory fakes that can persist and then throw:

```swift
import XCTest
@testable import ReadlessCore

@MainActor
final class VoiceServiceSaveCoordinatorTests: XCTestCase {
    private let configuration = VoiceServiceConfiguration.doubaoV3(
        resourceID: "seed-tts-2.0",
        speaker: "saturn-speaker"
    )

    func testNormalSavePersistsConfigurationAndCredential() {
        let settings = SaveSettingsFake()
        let credentials = SaveCredentialsFake()
        let saver = VoiceServiceSaveCoordinator(
            settings: settings,
            credentials: credentials
        )

        XCTAssertNil(
            saver.save(
                configuration: configuration,
                credential: "new-api-key"
            )
        )
        XCTAssertEqual(settings.configuration, configuration)
        XCTAssertEqual(credentials.values[.doubaoV3], "new-api-key")
    }

    func testSaveRecoversWhenSettingsPersistsBeforeThrowing() {
        let settings = SaveSettingsFake(throwsAfterSave: true)
        let credentials = SaveCredentialsFake()
        let saver = VoiceServiceSaveCoordinator(
            settings: settings,
            credentials: credentials
        )

        XCTAssertNil(
            saver.save(
                configuration: configuration,
                credential: "new-api-key"
            )
        )
    }

    func testSaveRecoversWhenCredentialPersistsBeforeThrowing() {
        let settings = SaveSettingsFake(configuration: configuration)
        let credentials = SaveCredentialsFake(throwsAfterSave: true)
        let saver = VoiceServiceSaveCoordinator(
            settings: settings,
            credentials: credentials
        )

        XCTAssertNil(
            saver.save(
                configuration: configuration,
                credential: "new-api-key"
            )
        )
    }

    func testSaveFailsWhenOnlyCredentialPersisted() {
        let settings = SaveSettingsFake(
            persistBeforeThrow: false,
            throwsAfterSave: true
        )
        let credentials = SaveCredentialsFake()
        let saver = VoiceServiceSaveCoordinator(
            settings: settings,
            credentials: credentials
        )

        XCTAssertEqual(
            saver.save(
                configuration: configuration,
                credential: "new-api-key"
            ),
            .persistenceFailed
        )
    }

    func testSaveFailsWhenOnlyConfigurationPersisted() {
        let settings = SaveSettingsFake(configuration: configuration)
        let credentials = SaveCredentialsFake(
            persistBeforeThrow: false,
            throwsAfterSave: true
        )
        let saver = VoiceServiceSaveCoordinator(
            settings: settings,
            credentials: credentials
        )

        XCTAssertEqual(
            saver.save(
                configuration: configuration,
                credential: "new-api-key"
            ),
            .persistenceFailed
        )
    }
}

private enum SaveFailure: Error {
    case requested
}

@MainActor
private final class SaveSettingsFake: VoiceServiceSettingsSaving {
    var configuration: VoiceServiceConfiguration?
    var profiles: VoiceServiceProfiles {
        guard let configuration else {
            return VoiceServiceProfiles()
        }
        return VoiceServiceProfiles.migrated(from: configuration)
    }
    private let persistBeforeThrow: Bool
    private let throwsAfterSave: Bool

    init(
        configuration: VoiceServiceConfiguration? = nil,
        persistBeforeThrow: Bool = true,
        throwsAfterSave: Bool = false
    ) {
        self.configuration = configuration
        self.persistBeforeThrow = persistBeforeThrow
        self.throwsAfterSave = throwsAfterSave
    }

    func save(configuration: VoiceServiceConfiguration) throws {
        if persistBeforeThrow {
            self.configuration = configuration
        }
        if throwsAfterSave {
            throw SaveFailure.requested
        }
    }

    func selectDoubaoVersion(_ version: DoubaoAPIVersion) {}
}

@MainActor
private final class SaveCredentialsFake: VoiceServiceCredentialStoring {
    var values: [VoiceCredentialSlot: String] = [:]
    private let persistBeforeThrow: Bool
    private let throwsAfterSave: Bool

    init(
        persistBeforeThrow: Bool = true,
        throwsAfterSave: Bool = false
    ) {
        self.persistBeforeThrow = persistBeforeThrow
        self.throwsAfterSave = throwsAfterSave
    }

    func hasCredential(for slot: VoiceCredentialSlot) -> Bool {
        values[slot]?.isEmpty == false
    }

    func credential(for slot: VoiceCredentialSlot) throws -> String? {
        values[slot]
    }

    func saveCredential(
        _ credential: String,
        for slot: VoiceCredentialSlot
    ) throws {
        if persistBeforeThrow {
            values[slot] = credential
        }
        if throwsAfterSave {
            throw SaveFailure.requested
        }
    }

    func removeCredential(for slot: VoiceCredentialSlot) throws {
        values.removeValue(forKey: slot)
    }
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-saveverify-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-saveverify-swiftpm-cache \
swift test --disable-sandbox \
  --filter VoiceServiceSaveCoordinatorTests
```

Expected: compilation fails because `VoiceServiceSaveCoordinator` and `VoiceServiceSettingsSaving` do not exist.

- [ ] **Step 3: Add the settings-saving boundary**

Add this protocol to `readless/Core/VoiceServiceStore.swift` immediately after `VoiceServiceConfigurationStoring`:

```swift
@MainActor
protocol VoiceServiceSettingsSaving: VoiceServiceConfigurationStoring {
    func save(configuration: VoiceServiceConfiguration) throws
}
```

Change the declaration in `readless/System/VoiceServiceSettingsStore.swift` to:

```swift
@MainActor
final class VoiceServiceSettingsStore: VoiceServiceSettingsSaving {
```

- [ ] **Step 4: Implement the minimal durable save coordinator**

Create `readless/Core/VoiceServiceSaveCoordinator.swift`:

```swift
import Foundation

@MainActor
final class VoiceServiceSaveCoordinator {
    private let settings: VoiceServiceSettingsSaving
    private let credentials: VoiceServiceCredentialStoring

    init(
        settings: VoiceServiceSettingsSaving,
        credentials: VoiceServiceCredentialStoring
    ) {
        self.settings = settings
        self.credentials = credentials
    }

    func save(
        configuration: VoiceServiceConfiguration,
        credential: String
    ) -> VoiceServiceSaveError? {
        let newCredential = credential.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let validationError = configuration.validationError {
            return .validation(validationError)
        }

        do {
            if !newCredential.isEmpty {
                if let error = VoiceServiceConfigurationValidator.saveError(
                    for: configuration.provider,
                    configuration: configuration,
                    credential: newCredential
                ) {
                    return error
                }
                try credentials.saveCredential(
                    newCredential,
                    for: configuration.credentialSlot
                )
            }
            try settings.save(configuration: configuration)
            return nil
        } catch {
            return persistedStateMatches(configuration)
                ? nil
                : .persistenceFailed
        }
    }

    private func persistedStateMatches(
        _ configuration: VoiceServiceConfiguration
    ) -> Bool {
        settings.configuration == configuration
            && credentials.hasCredential(
                for: configuration.credentialSlot
            )
    }
}
```

Add `"Core/VoiceServiceSaveCoordinator.swift"` to the `ReadlessCore` source list in `Package.swift`.

- [ ] **Step 5: Run the focused tests and verify GREEN**

Run the command from Step 2.

Expected: 5 tests executed, 0 failures.

- [ ] **Step 6: Commit the coordinator**

```bash
git add Package.swift \
  readless/Core/VoiceServiceStore.swift \
  readless/Core/VoiceServiceSaveCoordinator.swift \
  readless/System/VoiceServiceSettingsStore.swift \
  Tests/ReadlessCoreTests/VoiceServiceSaveCoordinatorTests.swift
git commit -m "fix: verify durable voice service saves"
```

### Task 2: Connect the coordinator to the app runtime

**Files:**
- Modify: `readless/AppDelegate.swift`
- Modify: `Tests/ReadlessCoreTests/VoiceServiceSettingsLayoutTests.swift`

- [ ] **Step 1: Add a failing runtime wiring assertion**

Add this test to `VoiceServiceSettingsLayoutTests`:

```swift
func testRuntimeDelegatesVoiceServiceSavingToCoordinator() throws {
    let source = try appDelegateSource()

    XCTAssertTrue(source.contains("VoiceServiceSaveCoordinator("))
    XCTAssertTrue(source.contains("voiceServiceSaver.save("))
    XCTAssertFalse(
        source.contains("try credentialStore.saveCredential(")
    )
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-saveverify-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-saveverify-swiftpm-cache \
swift test --disable-sandbox \
  --filter VoiceServiceSettingsLayoutTests/testRuntimeDelegatesVoiceServiceSavingToCoordinator
```

Expected: test fails because `AppDelegate` still performs saving directly.

- [ ] **Step 3: Wire the coordinator into `AppDelegate`**

Add a retained property:

```swift
private var voiceServiceSaver: VoiceServiceSaveCoordinator?
```

After constructing the local credential store, create and retain the coordinator:

```swift
let voiceServiceSaver = VoiceServiceSaveCoordinator(
    settings: voiceServiceSettings,
    credentials: credentialStore
)
// ...
self.voiceServiceSaver = voiceServiceSaver
```

Replace the body of the private `saveVoiceService` method with:

```swift
private func saveVoiceService(
    configuration: VoiceServiceConfiguration,
    credential: String
) -> VoiceServiceSaveError? {
    guard let voiceServiceSaver else {
        return .persistenceFailed
    }

    if let error = voiceServiceSaver.save(
        configuration: configuration,
        credential: credential
    ) {
        return error
    }

    if state.isOnboardingVisible,
       state.onboardingStep == .configuration {
        state.advanceOnboarding(after: .configurationSaved)
    }
    return nil
}
```

- [ ] **Step 4: Run the focused layout tests and app build**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-saveverify-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-saveverify-swiftpm-cache \
swift test --disable-sandbox --filter VoiceServiceSettingsLayoutTests
```

Expected: all layout tests pass.

Then run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-saveverify-xcode-cache \
xcodebuild -project readless.xcodeproj -scheme readless \
  -configuration Debug \
  -derivedDataPath /tmp/readless-saveverify-derived \
  build CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit runtime wiring**

```bash
git add readless/AppDelegate.swift \
  Tests/ReadlessCoreTests/VoiceServiceSettingsLayoutTests.swift
git commit -m "fix: recover completed voice service saves"
```

### Task 3: Doubao-specific invalid API Key diagnostics

**Files:**
- Modify: `Tests/ReadlessCoreTests/CloudSpeechRequestTests.swift`
- Modify: `Tests/ReadlessCoreTests/DoubaoV3SpeechProviderSourceTests.swift`
- Modify: `Tests/ReadlessCoreTests/AppStateTests.swift`
- Modify: `readless/Core/ReadingModels.swift`
- Modify: `readless/Core/CloudSpeechRequests.swift`
- Modify: `readless/System/DoubaoV3SpeechProvider.swift`
- Modify: `readless/AppState.swift`
- Modify: `readless/MainWindowView.swift`
- Modify: `readless/MiniPlayerView.swift`

- [ ] **Step 1: Write failing provider-specific mapping tests**

Keep the existing generic HTTP test asserting that `CloudSpeechErrorMapper.map(statusCode: 401)` returns `.voiceServiceCredentialInvalid`. Add:

```swift
func testDoubaoUnauthorizedResponseMapsToSpecificAPIKeyError() {
    XCTAssertEqual(
        CloudSpeechErrorMapper.mapDoubaoV3HTTPStatus(401),
        .doubaoAPIKeyInvalid
    )
}
```

Update `testDoubaoV3HTTPResponseMapsCredentialMessage` to expect:

```swift
.failure(.doubaoAPIKeyInvalid)
```

In `DoubaoV3SpeechProviderSourceTests.testProviderClassifiesHTTPAndTransportFailures`, replace the generic mapper assertion with:

```swift
XCTAssertTrue(
    source.contains("CloudSpeechErrorMapper.mapDoubaoV3HTTPStatus(")
)
```

Add this test to `AppStateTests`:

```swift
func testDoubaoAPIKeyErrorExplainsWhichCredentialToUse() {
    XCTAssertEqual(
        ReadingError.doubaoAPIKeyInvalid.userMessage,
        "豆包 API Key 无效。请填写新版控制台“API Key 管理”中的 API Key，不要填写 Access Token。"
    )
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-saveverify-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-saveverify-swiftpm-cache \
swift test --disable-sandbox \
  --filter 'CloudSpeechRequestTests|AppStateTests/testDoubaoAPIKeyError'
```

Expected: compilation fails because `.doubaoAPIKeyInvalid` and `mapDoubaoV3HTTPStatus` do not exist.

- [ ] **Step 3: Add the dedicated error and user message**

Add to `ReadingError` in `readless/Core/ReadingModels.swift`:

```swift
case doubaoAPIKeyInvalid
```

Add to `ReadingError.userMessage` in `readless/AppState.swift`:

```swift
case .doubaoAPIKeyInvalid:
    "豆包 API Key 无效。请填写新版控制台“API Key 管理”中的 API Key，不要填写 Access Token。"
```

Add `.doubaoAPIKeyInvalid` beside `.voiceServiceCredentialInvalid` in the exhaustive error switches in `MainWindowView.swift` and `MiniPlayerView.swift`.

- [ ] **Step 4: Add Doubao-specific HTTP and protocol mapping**

Add to `CloudSpeechErrorMapper`:

```swift
static func mapDoubaoV3HTTPStatus(_ statusCode: Int) -> ReadingError {
    switch statusCode {
    case 401, 403:
        .doubaoAPIKeyInvalid
    default:
        map(statusCode: statusCode)
    }
}
```

In `mapDoubaoMessage`, return `.doubaoAPIKeyInvalid` when the normalized message contains `auth`, `grant`, or `api key`.

In `knownHTTPStatusMapping`, return `.doubaoAPIKeyInvalid` for protocol codes `401` and `403`.

In `DoubaoV3SpeechProvider.mapHTTPFailure`, replace both generic status calls with:

```swift
CloudSpeechErrorMapper.mapDoubaoV3HTTPStatus(statusCode)
```

- [ ] **Step 5: Run focused and full Swift tests**

Run the focused command from Step 2.

Expected: focused tests pass.

Then run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-saveverify-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-saveverify-swiftpm-cache \
swift test --disable-sandbox
```

Expected: all tests pass, including the four new coordinator tests and provider-specific error tests.

- [ ] **Step 6: Commit API Key diagnostics**

```bash
git add readless/Core/ReadingModels.swift \
  readless/Core/CloudSpeechRequests.swift \
  readless/System/DoubaoV3SpeechProvider.swift \
  readless/AppState.swift \
  readless/MainWindowView.swift \
  readless/MiniPlayerView.swift \
  Tests/ReadlessCoreTests/CloudSpeechRequestTests.swift \
  Tests/ReadlessCoreTests/DoubaoV3SpeechProviderSourceTests.swift \
  Tests/ReadlessCoreTests/AppStateTests.swift
git commit -m "fix: explain invalid doubao API keys"
```

### Task 4: Full verification, integration, and signed relaunch

**Files:**
- Verify all modified files.
- Preserve the existing unstaged `SidebarAppIcon` hunk in the main workspace.

- [ ] **Step 1: Run all automated verification in the worktree**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-saveverify-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-saveverify-swiftpm-cache \
swift test --disable-sandbox
```

Expected: all Swift tests pass with 0 failures.

Run from the outer repository root:

```bash
node --test tests/*.test.mjs
```

Expected: 18 tests pass, 0 fail.

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-saveverify-xcode-cache \
xcodebuild -project readless.xcodeproj -scheme readless \
  -configuration Debug \
  -derivedDataPath /tmp/readless-saveverify-derived \
  build CODE_SIGNING_ALLOWED=NO
git diff --check main...HEAD
git status --short
```

Expected: build succeeds, diff check is clean, and the worktree has no uncommitted files.

- [ ] **Step 2: Review the final diff against the approved spec**

Verify:

- Save recovery returns success only when both the exact active configuration and the credential slot are durable.
- Generic OpenAI-compatible `401` remains `.voiceServiceCredentialInvalid`.
- Doubao V3 `401`, `403`, and `Invalid X-Api-Key` payloads map to `.doubaoAPIKeyInvalid`.
- No API Key value is logged, committed, or included in tests.

- [ ] **Step 3: Integrate locally without staging the user icon hunk**

From the main workspace, confirm `git status --short` shows only `readless/MainWindowView.swift`. Merge the feature branch. If the main-window file overlaps, stage only the credential/error hunk with `git add -p`, leaving the `SidebarAppIcon` hunk unstaged. Confirm with:

```bash
git diff --cached -- readless/MainWindowView.swift
git diff -- readless/MainWindowView.swift
```

Expected: the cached diff contains only this fix; the unstaged diff contains only `SidebarAppIcon`.

- [ ] **Step 4: Re-run merged tests and produce the signed app**

Run the full Swift and Node test commands again in the main workspace. Then build the signed app outside the restricted sandbox:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-saveverify-signed-cache \
xcodebuild -project readless.xcodeproj -scheme readless \
  -configuration Debug \
  -derivedDataPath /tmp/readless-saveverify-signed-derived \
  build
```

Expected: `** BUILD SUCCEEDED **` and `codesign --verify --deep --strict` succeeds.

- [ ] **Step 5: Stop debug/preview instances and launch one signed instance**

Resolve exact Readless PIDs with `pgrep -fl readless`, stop only Xcode Preview/debug instances, and launch:

```bash
open -n /tmp/readless-saveverify-signed-derived/Build/Products/Debug/readless.app
```

Confirm exactly one intended signed instance remains. The saved invalid key should now enable the test button; pressing it should show the dedicated invalid API Key message. After the user replaces it with a valid API Key from the official API Key management page, the built-in sentence and selection shortcut should play audio.
