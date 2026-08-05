# Save Success UI Reconciliation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the false orange persistence error when the requested voice configuration and credential were durably saved.

**Architecture:** Keep `VoiceServiceSaveCoordinator` as the save authority and strengthen its post-error reconciliation to compare the exact submitted credential instead of merely checking slot occupancy. Clear stale editor error state before each save attempt, while leaving remote provider validation separate from local persistence.

**Tech Stack:** Swift 5, SwiftUI, Foundation `UserDefaults`, XCTest, Swift Package Manager, Xcode.

---

### Task 1: Verify the exact credential after a recoverable storage exception

**Files:**
- Modify: `Tests/ReadlessCoreTests/VoiceServiceSaveCoordinatorTests.swift`
- Modify: `readless/Core/VoiceServiceSaveCoordinator.swift`

- [ ] **Step 1: Write the failing coordinator tests**

Add a test where an old credential already occupies `.doubaoV3`, the replacement write throws before changing it, and the requested configuration is already stored. Assert that `save` returns `.persistenceFailed`. Add a second test that submits an empty credential, persists the configuration before throwing, retains a non-empty existing credential, and returns success.

```swift
func testSaveDoesNotMistakeOlderCredentialForReplacement() {
    let settings = SaveSettingsFake(configuration: configuration)
    let credentials = SaveCredentialsFake(
        values: [.doubaoV3: "old-api-key"],
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

func testSaveWithoutReplacementAcceptsExistingCredential() {
    let settings = SaveSettingsFake(throwsAfterSave: true)
    let credentials = SaveCredentialsFake(
        values: [.doubaoV3: "existing-api-key"]
    )
    let saver = VoiceServiceSaveCoordinator(
        settings: settings,
        credentials: credentials
    )

    XCTAssertNil(
        saver.save(configuration: configuration, credential: "")
    )
}
```

Update `SaveCredentialsFake` to accept an initial `values` dictionary.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-save-ui-red-cache \
swift test --filter VoiceServiceSaveCoordinatorTests
```

Expected: `testSaveDoesNotMistakeOlderCredentialForReplacement` fails because the existing implementation only calls `hasCredential`.

- [ ] **Step 3: Implement exact post-save reconciliation**

Pass the normalized submitted credential into `persistedStateMatches`. When it is non-empty, read the slot and compare the stored value exactly; when it is empty, require only an existing non-empty credential.

```swift
private func persistedStateMatches(
    _ configuration: VoiceServiceConfiguration,
    expectedCredential: String?
) -> Bool {
    guard settings.configuration == configuration else {
        return false
    }
    if let expectedCredential {
        return (try? credentials.credential(
            for: configuration.credentialSlot
        )) == expectedCredential
    }
    return credentials.hasCredential(
        for: configuration.credentialSlot
    )
}
```

Call it with `expectedCredential: newCredential.isEmpty ? nil : newCredential` inside the catch block.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the command from Step 2.

Expected: all `VoiceServiceSaveCoordinatorTests` pass with zero failures.

- [ ] **Step 5: Commit Task 1**

```bash
git add readless/Core/VoiceServiceSaveCoordinator.swift Tests/ReadlessCoreTests/VoiceServiceSaveCoordinatorTests.swift
git commit -m "fix: verify exact saved voice credential"
```

### Task 2: Clear stale editor errors at the start of every save attempt

**Files:**
- Modify: `Tests/ReadlessCoreTests/VoiceServiceSettingsLayoutTests.swift`
- Modify: `readless/MainWindowView.swift`

- [ ] **Step 1: Write the failing source regression test**

Add a source test that locates `private func save()` and asserts `error = nil` occurs before `error = actions.saveVoiceService(configuration, credential)`.

```swift
func testEditorClearsStaleErrorBeforeSaving() throws {
    let source = try String(
        contentsOfFile: sourceRoot + "/readless/MainWindowView.swift",
        encoding: .utf8
    )
    let saveStart = try XCTUnwrap(
        source.range(of: "private func save()")
    )
    let saveSource = source[saveStart.lowerBound...]
    let clear = try XCTUnwrap(saveSource.range(of: "error = nil"))
    let call = try XCTUnwrap(
        saveSource.range(
            of: "error = actions.saveVoiceService(configuration, credential)"
        )
    )
    XCTAssertLessThan(clear.lowerBound, call.lowerBound)
}
```

- [ ] **Step 2: Run the focused layout test and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-save-ui-layout-red-cache \
swift test --filter VoiceServiceSettingsLayoutTests
```

Expected: the new test fails because `save()` does not clear the stale error before building and submitting the configuration.

- [ ] **Step 3: Add the minimal UI state reset**

Add this as the first statement in `VoiceServiceEditor.save()`:

```swift
error = nil
```

Keep the coordinator result assignment and the existing success-only credential clearing unchanged.

- [ ] **Step 4: Run the focused layout test and verify GREEN**

Run the command from Step 2.

Expected: all `VoiceServiceSettingsLayoutTests` pass with zero failures.

- [ ] **Step 5: Commit Task 2**

```bash
git add readless/MainWindowView.swift Tests/ReadlessCoreTests/VoiceServiceSettingsLayoutTests.swift
git commit -m "fix: clear stale voice save errors"
```

### Task 3: Verify the complete application and launch a single signed instance

**Files:**
- No source changes expected.

- [ ] **Step 1: Run the full Swift package tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-save-ui-full-cache \
swift test
```

Expected: all tests pass with zero failures.

- [ ] **Step 2: Run the outer product tests**

From `/Users/chenxiaofeng/Documents/Tare code file/readless`:

```bash
node --test tests/*.test.mjs
```

Expected: 18 tests pass with zero failures.

- [ ] **Step 3: Build and sign the macOS app**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-save-ui-signed-cache \
xcodebuild -project readless.xcodeproj -scheme readless \
  -configuration Debug \
  -derivedDataPath /tmp/readless-save-ui-signed-derived build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify the application signature**

```bash
/usr/bin/codesign --verify --deep --strict --verbose=2 \
  /tmp/readless-save-ui-signed-derived/Build/Products/Debug/readless.app
```

Expected: the app is valid on disk and satisfies its designated requirement.

- [ ] **Step 5: Integrate locally without committing the user's sidebar icon change**

Merge the feature branch into `main`, verify that `readless/MainWindowView.swift` still contains the user's uncommitted `SidebarAppIcon` diff, rerun the full tests on `main`, close only exact Readless app/debugserver processes, and launch exactly one newly signed app instance.

