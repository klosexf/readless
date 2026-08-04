# Local Credentials and Doubao HTTP Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist voice credentials without macOS Keychain, use Doubao V3's official HTTP endpoint, and restore selection-shortcut speech after configuration is saved.

**Architecture:** Add a file-backed `VoiceServiceCredentialStoring` implementation with dependency-injected storage URL and strict POSIX permissions. Keep the existing coordinator and speech-engine boundaries, but replace the Doubao V3 binary WebSocket request/response path with an HTTP JSON request and newline-delimited JSON audio decoder. Wire the runtime to one shared local credential store and update user-facing storage wording.

**Tech Stack:** Swift 6, SwiftUI/AppKit, Foundation `FileManager`/`URLSession`, XCTest, Swift Package Manager, Xcode 26.

---

## File Structure

- Create `readless/System/LocalCredentialStore.swift`: file-backed implementation of `VoiceServiceCredentialStoring`.
- Create `Tests/ReadlessCoreTests/LocalCredentialStoreTests.swift`: real filesystem round-trip, corruption, and POSIX permission tests.
- Modify `Package.swift`: compile `LocalCredentialStore.swift` instead of `KeychainCredentialStore.swift` in the core test target.
- Modify `readless/AppDelegate.swift`: instantiate and share `LocalCredentialStore`.
- Modify `readless/Core/CloudSpeechRequests.swift`: build the V3 HTTP request and decode its JSON chunks.
- Modify `Tests/ReadlessCoreTests/CloudSpeechRequestTests.swift`: replace binary WebSocket assertions with HTTP request/response behavior.
- Modify `readless/System/DoubaoV3SpeechProvider.swift`: use `URLSessionDataTask` and the HTTP decoder.
- Modify `Tests/ReadlessCoreTests/DoubaoV3SpeechProviderSourceTests.swift`: assert the provider uses HTTP data tasks and response classification.
- Modify `readless/Core/VoiceServiceModels.swift`: make persistence failure storage-neutral.
- Modify `readless/MainWindowView.swift`: state that credentials are stored in local Readless application data, not Keychain.
- Modify `Tests/ReadlessCoreTests/VoiceServiceSettingsLayoutTests.swift`: enforce the new runtime and UI wording.

### Task 1: Add the local credential store

**Files:**
- Create: `Tests/ReadlessCoreTests/LocalCredentialStoreTests.swift`
- Create: `readless/System/LocalCredentialStore.swift`
- Modify: `Package.swift`
- Modify: `Tests/ReadlessCoreTests/VoiceServiceStoreTests.swift`

- [ ] **Step 1: Write failing local-store tests**

Create tests that construct `LocalCredentialStore(fileURL:)` in a unique temporary directory. Cover missing-file lookup, separate slot round trips, replacement, removal, corrupt JSON, and permissions:

```swift
import Foundation
import XCTest
@testable import ReadlessCore

@MainActor
final class LocalCredentialStoreTests: XCTestCase {
    private var rootURL: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalCredentialStoreTests-\(UUID().uuidString)")
        fileURL = rootURL
            .appendingPathComponent("Readless", isDirectory: true)
            .appendingPathComponent("voice-credentials-v1.json")
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    func testMissingFileHasNoCredential() throws {
        let store = LocalCredentialStore(fileURL: fileURL)
        XCTAssertNil(try store.credential(for: .doubaoV3))
        XCTAssertFalse(store.hasCredential(for: .doubaoV3))
    }

    func testCredentialsRoundTripReplaceAndRemoveBySlot() throws {
        let store = LocalCredentialStore(fileURL: fileURL)
        try store.saveCredential("v3-key", for: .doubaoV3)
        try store.saveCredential("compatible-key", for: .openAICompatible)
        try store.saveCredential("replacement", for: .doubaoV3)
        XCTAssertEqual(try store.credential(for: .doubaoV3), "replacement")
        XCTAssertEqual(
            try store.credential(for: .openAICompatible),
            "compatible-key"
        )
        try store.removeCredential(for: .doubaoV3)
        XCTAssertNil(try store.credential(for: .doubaoV3))
        XCTAssertEqual(
            try store.credential(for: .openAICompatible),
            "compatible-key"
        )
    }

    func testStoreCreatesPrivateDirectoryAndFile() throws {
        let store = LocalCredentialStore(fileURL: fileURL)
        try store.saveCredential("secret", for: .doubaoV3)
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: fileURL.deletingLastPathComponent().path
        )
        let fileAttributes = try FileManager.default.attributesOfItem(
            atPath: fileURL.path
        )
        XCTAssertEqual(
            (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue,
            0o700
        )
        XCTAssertEqual(
            (fileAttributes[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
    }

    func testCorruptCredentialFileThrows() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)
        let store = LocalCredentialStore(fileURL: fileURL)
        XCTAssertThrowsError(try store.credential(for: .doubaoV3))
    }
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-local-credential-clang \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-local-credential-swiftpm \
xcrun swift test --filter LocalCredentialStoreTests
```

Expected: compilation fails because `LocalCredentialStore` does not exist.

- [ ] **Step 3: Implement the minimal file-backed store**

Add `readless/System/LocalCredentialStore.swift`:

```swift
import Foundation

enum LocalCredentialStoreError: Error {
    case applicationSupportUnavailable
    case invalidFile
    case persistenceFailed
}

@MainActor
final class LocalCredentialStore: VoiceServiceCredentialStoring {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else if let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            self.fileURL = applicationSupport
                .appendingPathComponent("Readless", isDirectory: true)
                .appendingPathComponent("voice-credentials-v1.json")
        } else {
            self.fileURL = URL(fileURLWithPath: "/dev/null/readless-credentials")
        }
    }

    func hasCredential(for slot: VoiceCredentialSlot) -> Bool {
        (try? credential(for: slot))?.isEmpty == false
    }

    func credential(for slot: VoiceCredentialSlot) throws -> String? {
        try load()[slot.rawValue]
    }

    func saveCredential(
        _ credential: String,
        for slot: VoiceCredentialSlot
    ) throws {
        var values = try load()
        values[slot.rawValue] = credential
        try persist(values)
    }

    func removeCredential(for slot: VoiceCredentialSlot) throws {
        var values = try load()
        values.removeValue(forKey: slot.rawValue)
        try persist(values)
    }

    private func load() throws -> [String: String] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        do {
            return try decoder.decode(
                [String: String].self,
                from: Data(contentsOf: fileURL)
            )
        } catch {
            throw LocalCredentialStoreError.invalidFile
        }
    }

    private func persist(_ values: [String: String]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directoryURL.path
            )
            try encoder.encode(values).write(to: fileURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            throw LocalCredentialStoreError.persistenceFailed
        }
    }
}
```

Add `System/LocalCredentialStore.swift` to the explicit `sources` list in `Package.swift`, remove `System/KeychainCredentialStore.swift` from that list, and add the legacy file to `exclude` so SwiftPM does not report it as unhandled. Remove `testKeychainUsesLegacyCredentialOnlyForV1`; `LocalCredentialStoreTests` now owns persistence and slot-isolation coverage without touching Keychain.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the Step 2 command again.

Expected: 4 tests pass with 0 failures.

- [ ] **Step 5: Commit the local-store behavior**

```bash
git add Package.swift readless/System/LocalCredentialStore.swift \
  Tests/ReadlessCoreTests/LocalCredentialStoreTests.swift \
  Tests/ReadlessCoreTests/VoiceServiceStoreTests.swift
git commit -m "fix: persist voice credentials in local app data"
```

### Task 2: Replace Doubao V3 WebSocket packets with HTTP JSON

**Files:**
- Modify: `Tests/ReadlessCoreTests/CloudSpeechRequestTests.swift`
- Modify: `readless/Core/CloudSpeechRequests.swift`

- [ ] **Step 1: Replace the V3 request test and add decoder tests**

Replace the binary packet assertions with a test that requires an HTTP POST to `https://openspeech.bytedance.com/api/v3/tts/unidirectional`, `application/json`, the three `X-Api-*` headers, and a directly decodable JSON body. Add tests for ordered Base64 chunk concatenation, invalid Base64, empty audio, and service-message classification:

```swift
func testDoubaoV3RequestUsesHTTPHeadersAndJSONBody() throws {
    let requestID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let request = try DoubaoV3RequestBuilder.make(
        configuration: .doubaoV3(
            resourceID: "seed-tts-2.0",
            speaker: "test-speaker"
        ),
        apiKey: "unit-test-key",
        text: "测试",
        rate: 1,
        requestID: requestID
    )
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(
        request.url?.absoluteString,
        "https://openspeech.bytedance.com/api/v3/tts/unidirectional"
    )
    XCTAssertEqual(
        request.value(forHTTPHeaderField: "Content-Type"),
        "application/json"
    )
    let body = try XCTUnwrap(
        JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody))
            as? [String: Any]
    )
    let parameters = try XCTUnwrap(body["req_params"] as? [String: Any])
    XCTAssertEqual(parameters["text"] as? String, "测试")
    XCTAssertEqual(parameters["speaker"] as? String, "test-speaker")
}

func testDoubaoV3HTTPResponseMergesAudioChunks() {
    let response = Data(
        """
        {"code":0,"data":"AQI="}
        {"code":0,"data":"AwQ="}
        {"code":20000000,"message":"OK"}
        """.utf8
    )
    XCTAssertEqual(
        DoubaoV3HTTPResponseDecoder.decode(response),
        .success(Data([1, 2, 3, 4]))
    )
}

func testDoubaoV3HTTPResponseRejectsInvalidBase64() {
    let response = Data(#"{"code":0,"data":"%%%"}"#.utf8)
    XCTAssertEqual(
        DoubaoV3HTTPResponseDecoder.decode(response),
        .failure(.voiceServiceResponseInvalid)
    )
}

func testDoubaoV3HTTPResponseMapsCredentialMessage() {
    let response = Data(
        #"{"code":45000000,"message":"invalid api key"}"#.utf8
    )
    XCTAssertEqual(
        DoubaoV3HTTPResponseDecoder.decode(response),
        .failure(.voiceServiceCredentialInvalid)
    )
}
```

- [ ] **Step 2: Run the focused request tests and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-local-credential-clang \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-local-credential-swiftpm \
xcrun swift test --filter CloudSpeechRequestTests
```

Expected: the existing builder still returns `wss`, and `DoubaoV3HTTPResponseDecoder` is undefined.

- [ ] **Step 3: Implement the HTTP request and response decoder**

Change the V3 endpoint to HTTPS, set `httpMethod = "POST"`, set `Content-Type`, and assign the JSON payload directly to `httpBody`. Remove the binary packet builder, binary packet response types, collector, packet decoder, and now-unused `Data` integer helpers.

Add a decoder that splits UTF-8 response content on newlines, JSON-decodes every non-empty line, accepts service codes `0` and `20000000`, appends every valid Base64 `data` value, maps other codes/messages through `CloudSpeechErrorMapper.mapDoubaoV3Error`, and rejects malformed or empty audio responses.

- [ ] **Step 4: Run the focused request tests and verify GREEN**

Run the Step 2 command again.

Expected: all `CloudSpeechRequestTests` pass.

- [ ] **Step 5: Commit the protocol change**

```bash
git add readless/Core/CloudSpeechRequests.swift \
  Tests/ReadlessCoreTests/CloudSpeechRequestTests.swift
git commit -m "fix: build doubao v3 HTTP synthesis requests"
```

### Task 3: Use the HTTP provider and classify failures

**Files:**
- Modify: `Tests/ReadlessCoreTests/DoubaoV3SpeechProviderSourceTests.swift`
- Modify: `readless/System/DoubaoV3SpeechProvider.swift`

- [ ] **Step 1: Write the failing provider source test**

Require `URLSessionDataTask`, HTTP response validation, `CloudSpeechErrorMapper.map(statusCode:)`, and `DoubaoV3HTTPResponseDecoder.decode(data)`; reject `URLSessionWebSocketTask`, `.send(.data`, and `receiveNext()`.

- [ ] **Step 2: Run the provider test and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-local-credential-clang \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-local-credential-swiftpm \
xcrun swift test --filter DoubaoV3SpeechProviderSourceTests
```

Expected: failure because the provider still uses WebSocket APIs.

- [ ] **Step 3: Implement the HTTP data-task provider**

Replace `URLSessionWebSocketTask`, the collector, send/receive loop, and WebSocket cancellation with one `URLSessionDataTask`. In the completion callback:

1. Map `URLError.timedOut` to `.voiceServiceTimedOut` and other `URLError` values to `.voiceServiceNetworkUnavailable`.
2. Require an `HTTPURLResponse`; otherwise return network unavailable.
3. For non-2xx HTTP status codes, map 401/403/408/429/504 with `CloudSpeechErrorMapper.map(statusCode:)`; if the status is otherwise generic and response data contains a V3 service message, return the decoder's more specific failure.
4. Require non-empty data and pass it to `DoubaoV3HTTPResponseDecoder.decode`.
5. Clear the active task before invoking completion; `cancel()` cancels and clears it.

- [ ] **Step 4: Run the focused provider test and full request tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-local-credential-clang \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-local-credential-swiftpm \
xcrun swift test --filter DoubaoV3SpeechProviderSourceTests
```

Then rerun `CloudSpeechRequestTests`.

Expected: both suites pass.

- [ ] **Step 5: Commit the provider change**

```bash
git add readless/System/DoubaoV3SpeechProvider.swift \
  Tests/ReadlessCoreTests/DoubaoV3SpeechProviderSourceTests.swift
git commit -m "fix: synthesize doubao v3 speech over HTTP"
```

### Task 4: Wire local credentials and update user-facing wording

**Files:**
- Modify: `Tests/ReadlessCoreTests/VoiceServiceSettingsLayoutTests.swift`
- Modify: `readless/AppDelegate.swift`
- Modify: `readless/Core/VoiceServiceModels.swift`
- Modify: `readless/MainWindowView.swift`

- [ ] **Step 1: Write failing source and message tests**

Update source tests to require `LocalCredentialStore()`, forbid `KeychainCredentialStore()` in `AppDelegate`, require local-application-data wording in the settings view, forbid “钥匙串” in the credential form, and assert `VoiceServiceSaveError.persistenceFailed.userMessage` is `"无法保存语音服务设置，请重试。"`.

- [ ] **Step 2: Run focused tests and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-local-credential-clang \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-local-credential-swiftpm \
xcrun swift test --filter VoiceServiceSettingsLayoutTests
```

Expected: failures because runtime and UI still mention Keychain.

- [ ] **Step 3: Wire and word the local store**

- Change `AppDelegate.credentialStore` to `LocalCredentialStore?` and instantiate `LocalCredentialStore()`.
- Change `.persistenceFailed` to `"无法保存语音服务设置，请重试。"`.
- Change the help text to `"不会经过 Readless 的服务器。文字会直接发送给你配置的服务商；凭据仅保存在这台 Mac 的 Readless 应用数据中。"`.
- Change the empty credential prompt to `"凭据仅保存在这台 Mac"`.
- Rename source-test method names and assertions so no behavior refers to Keychain.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the Step 2 command again.

Expected: all settings layout tests pass.

- [ ] **Step 5: Commit runtime wiring separately from the user's icon work**

```bash
git add readless/AppDelegate.swift readless/Core/VoiceServiceModels.swift \
  readless/MainWindowView.swift \
  Tests/ReadlessCoreTests/VoiceServiceSettingsLayoutTests.swift
git commit -m "fix: use local voice credentials at runtime"
```

### Task 5: Verify the complete branch

**Files:**
- Modify only if a verified failure requires a scoped correction.

- [ ] **Step 1: Run all Swift tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-local-credential-clang \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-local-credential-swiftpm \
xcrun swift test
```

Expected: all tests pass with 0 failures.

- [ ] **Step 2: Build the macOS application**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project readless.xcodeproj -scheme readless \
  -configuration Debug \
  -derivedDataPath /tmp/readless-local-credentials-derived \
  build CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Inspect the branch diff and credential-safety invariants**

```bash
git diff --check main...HEAD
rg -n "KeychainCredentialStore\(|macOS 钥匙串|凭据保存在钥匙串" \
  readless Tests Package.swift
```

Expected: diff check exits 0; runtime/UI search finds no Keychain construction or Keychain storage claims. The unused legacy implementation file may still exist, but it must not be compiled by SwiftPM or constructed by the app.

### Task 6: Integrate without overwriting the existing icon edit

**Files:**
- Main workspace: preserve its existing `readless/MainWindowView.swift` icon hunk.

- [ ] **Step 1: Review main workspace status**

Confirm the only pre-existing change is the sidebar icon hunk in `readless/MainWindowView.swift`.

- [ ] **Step 2: Integrate code-only commits**

Cherry-pick Tasks 1–3 onto `main`. For Task 4, apply its `AppDelegate`, model, tests, and only the credential-related `MainWindowView` hunk without staging or modifying the pre-existing icon hunk.

- [ ] **Step 3: Run fresh verification on main**

Run the full Swift test command, Xcode build, and the repository's outer Node tests against the integrated main workspace.

- [ ] **Step 4: Launch the newly built signed Debug app**

Build with normal local signing from Xcode or `xcodebuild`, terminate the currently running old Readless process, and open the new app. Do not delete the old Keychain item; the new runtime never accesses it.

- [ ] **Step 5: Perform user-assisted live checks**

Ask the user to re-enter the API Key once, save, play the built-in test sentence, then select text in TextEdit or Safari and press `⌥R`. Confirm save success, no Keychain error, audio playback, and shortcut playback. Restart once and repeat the built-in test to prove persistence.
