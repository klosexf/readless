# 最近朗读记录 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在本机安全保存、重启后恢复并显示选区朗读和显式剪贴板朗读的最近三条完整正文记录。

**Architecture:** `ReadingCoordinator` 仅在当前语音会话的 started 回调中写入一条 `RecentReading`，并把存储返回的三条列表投影到 `ReadlessAppState`。新增的文件存储放在既有的 `System/LocalCredentialStore.swift`，复用私有目录和原子写入，避免修改 `Package.swift` 或 Xcode 工程。

**Tech Stack:** Swift 6、Foundation、SwiftUI、AppKit、XCTest、SwiftPM、Xcode。

---

### Task 1: 定义数据模型与可注入存储

**Files:**
- Modify: `readless/Core/ReadingModels.swift`
- Test: `Tests/ReadlessCoreTests/LocalCredentialStoreTests.swift`

- [ ] **Step 1: 先写失败测试**

```swift
func testRecentReadingRetainsFullTextSourceAndTimestamp() {
    let time = Date(timeIntervalSince1970: 1_700_000_000)
    let record = RecentReading(
        text: "记录正文 A",
        sourceApplication: "Safari",
        startedAt: time
    )
    XCTAssertEqual(record.text, "记录正文 A")
    XCTAssertEqual(record.sourceApplication, "Safari")
    XCTAssertEqual(record.startedAt, time)
}
```

- [ ] **Step 2: 确认测试红灯**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter LocalCredentialStoreTests/testRecentReadingRetainsFullTextSourceAndTimestamp`

Expected: FAIL，提示 `RecentReading` 不存在。

- [ ] **Step 3: 添加最小合约**

在 `ReadingModels.swift` 中定义：

```swift
struct RecentReading: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let text: String
    let sourceApplication: String
    let startedAt: Date

    init(id: UUID = UUID(), text: String, sourceApplication: String, startedAt: Date) {
        self.id = id
        self.text = text
        self.sourceApplication = sourceApplication
        self.startedAt = startedAt
    }
}

@MainActor
protocol RecentReadingStoring {
    func load() throws -> [RecentReading]
    func append(_ reading: RecentReading) throws -> [RecentReading]
}
```

- [ ] **Step 4: 确认绿灯并提交**

重跑 Step 2 命令，预期 PASS；提交 `readless/Core/ReadingModels.swift` 与其测试，信息为 `feat: define recent reading model`。

### Task 2: 实现私有 JSON 的三条上限存储

**Files:**
- Modify: `readless/System/LocalCredentialStore.swift`
- Modify: `Tests/ReadlessCoreTests/LocalCredentialStoreTests.swift`

- [ ] **Step 1: 先写失败测试**

在临时目录创建 `recentReadingsFileURL`，再加入：

```swift
func testRecentReadingsRoundTripKeepsNewestThree() throws {
    let store = LocalRecentReadingStore(fileURL: recentReadingsFileURL)
    for index in 0...3 {
        _ = try store.append(RecentReading(
            text: "记录 \(index)",
            sourceApplication: "Safari",
            startedAt: Date(timeIntervalSince1970: Double(index))
        ))
    }
    XCTAssertEqual(try store.load().map(\.text), ["记录 3", "记录 2", "记录 1"])
}

func testRecentReadingsStoreCreatesPrivateDirectoryAndFile() throws {
    let store = LocalRecentReadingStore(fileURL: recentReadingsFileURL)
    _ = try store.append(RecentReading(text: "记录", sourceApplication: "剪贴板", startedAt: .now))
    let directory = recentReadingsFileURL.deletingLastPathComponent()
    let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    let fileAttributes = try FileManager.default.attributesOfItem(atPath: recentReadingsFileURL.path)
    XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
}
```

- [ ] **Step 2: 确认红灯**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter LocalCredentialStoreTests/testRecentReadingsRoundTripKeepsNewestThree`

Expected: FAIL，`LocalRecentReadingStore` 不存在。

- [ ] **Step 3: 添加存储实现**

在 `LocalCredentialStore.swift` 的既有类后加 `@MainActor final class LocalRecentReadingStore: RecentReadingStoring`。默认 JSON 路径为 `Application Support/Readless/recent-readings-v1.json`，不与凭据文件混用；无文件时 `load()` 返回 `[]`；无效 JSON 抛 `LocalCredentialStoreError.invalidFile`。`append(_:)` 将新记录前插、按 `startedAt` 降序、保留前三条并返回实际保存列表。`persist(_:)` 用 `.atomic` 写入，并把父目录设为 `0o700`、文件设为 `0o600`；不得写入 `UserDefaults`。

- [ ] **Step 4: 确认绿灯并提交**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter LocalCredentialStoreTests`

Expected: PASS；提交 `readless/System/LocalCredentialStore.swift` 和测试，信息为 `feat: persist three recent readings locally`。

### Task 3: 只在成功启动的会话中新增记录

**Files:**
- Modify: `readless/Core/ReadingCoordinator.swift`
- Modify: `readless/AppState.swift`
- Modify: `Tests/ReadlessCoreTests/ReadingCoordinatorTests.swift`
- Modify: `Tests/ReadlessCoreTests/AppStateTests.swift`

- [ ] **Step 1: 先写失败测试**

添加可失败的 `RecentReadingStoreFake` 与固定时钟，测试下面三个行为：

```swift
func testStartedSelectionAddsRecentReading() {
    selection.result = .success(firstSnapshot)
    coordinator.handleReadShortcut()
    speech.start()
    XCTAssertEqual(history.readings.map(\.text), ["原文"])
    XCTAssertEqual(history.readings.first?.sourceApplication, "Safari")
}

func testStartedClipboardAddsRecentReading() {
    clipboard.value = "剪贴板记录"
    coordinator.readClipboard()
    speech.start()
    XCTAssertEqual(history.readings.first?.sourceApplication, "剪贴板")
}

func testSpeechFailureBeforeStartDoesNotAddRecentReading() {
    selection.result = .success(firstSnapshot)
    coordinator.handleReadShortcut()
    speech.fail(.speechFailed)
    XCTAssertTrue(history.readings.isEmpty)
}
```

- [ ] **Step 2: 确认红灯**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter ReadingCoordinatorTests/testStartedSelectionAddsRecentReading`

Expected: FAIL，协调器尚未接收 history 依赖。

- [ ] **Step 3: 最小状态机接入**

`ReadlessAppState` 添加 `@Published private(set) var recentReadings` 和只保留前三条的 `replaceRecentReadings(_:)`。新增 `.recentReadingsUnavailable` 与固定中文错误“最近朗读记录暂时无法保存，请稍后重试。”。

`ReadingCoordinator` 接收 `history: RecentReadingStoring` 和 `now: () -> Date = { .now }`。`start` 新增 `recordsInHistory`：选区、显式剪贴板传 `true`，内置测试语音传 `false`。每次启动只保存一个包含 session ID、正文、来源和标识的候选；现有 `didStart(sessionID:)` 在验证当前 session 且调用 `state.beginPlayback` 后，才将匹配候选 `append` 并同步 state。写入失败只用 `showNonInterruptingError` 展示该固定错误；无论成功或失败都清除候选，防止旧回调、重复回调或失败会话写入。

- [ ] **Step 4: 确认绿灯并提交**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter ReadingCoordinatorTests`

Expected: PASS；提交 Core、state 与测试，信息为 `feat: record started readings`。

### Task 4: 装配本地存储并替换占位 UI

**Files:**
- Modify: `readless/AppDelegate.swift`
- Modify: `readless/MainWindowView.swift`
- Modify: `readless/MenuBarController.swift`
- Modify: `Tests/ReadlessCoreTests/AppStateTests.swift`

- [ ] **Step 1: 先写失败源码回归测试**

```swift
func testRecentReadingsViewUsesPublishedStateInsteadOfSamples() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("readless/MainWindowView.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    XCTAssertTrue(source.contains("RecentReadingsView(state: state)"))
    XCTAssertFalse(source.contains("private let readings = ["))
}
```

- [ ] **Step 2: 确认红灯**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter AppStateTests/testRecentReadingsViewUsesPublishedStateInsteadOfSamples`

Expected: FAIL，当前界面仍使用样例数组。

- [ ] **Step 3: 写入最小运行时和 UI 实现**

`AppDelegate` 创建单个 `LocalRecentReadingStore`，启动时加载并交给 `state.replaceRecentReadings`，再将同一实例注入 coordinator；加载失败显示不含正文的 `.recentReadingsUnavailable`，但不阻止 App 启动。详情页面改为 `RecentReadingsView(state: state)`；空记录显示“还没有最近朗读记录”，非空 `ForEach(state.recentReadings)` 显示完整多行正文、来源和 `startedAt.formatted(date: .abbreviated, time: .shortened)`；副标题明确“完整正文仅保存在这台 Mac 上，最多保留三条。”。菜单栏根据 `state.recentReadings` 创建禁用的单行折叠预览；无记录显示“暂无最近朗读”。不新增重播、删除或清空。

- [ ] **Step 4: 确认绿灯并提交**

重跑 Step 2，预期 PASS；提交 AppDelegate、两个 UI 文件和测试，信息为 `feat: show recent readings in app`。

### Task 5: 完整验证与记录

**Files:**
- Modify: `progress.md`

- [ ] **Step 1: 完整 Core 测试**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test`

Expected: 0 failures。

- [ ] **Step 2: 完整 App 构建**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project readless.xcodeproj -scheme readless -configuration Debug -derivedDataPath /tmp/readless-recent-history-derived build CODE_SIGNING_ALLOWED=NO`

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 3: 泄露检查与手测**

Run: `git diff main...HEAD --check && rg -n 'print\\(|NSLog|os_log|UserDefaults' readless/Core/ReadingCoordinator.swift readless/System/LocalCredentialStore.swift readless/AppDelegate.swift`

Expected: diff 无输出，相关路径不向日志或 `UserDefaults` 写正文。

手测两种入口、三条上限、重启恢复，以及未配置、空剪贴板和启动失败不生成记录、不打断播放。使用非敏感测试文字，且不要把正文记入 `progress.md`。

- [ ] **Step 4: 更新进度并提交**

在 `progress.md` 写明用户已授权完整正文仅本机三条、真实测试/构建结果、手测或阻塞与回滚提交；提交信息为 `docs: record recent reading history verification`。
