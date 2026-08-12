# Recent Readings Collapse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse long recent-reading bodies to 160 characters and let each card independently expand or collapse its full text.

**Architecture:** A small pure Core value type in the existing `ReadingModels.swift` source owns the character-count decision and summary string, keeping Unicode-safe truncation unit-testable without changing SwiftPM configuration. `RecentReadingsView` owns only transient per-record expansion state, chooses the Core display text, and animates card-height changes; it neither reads nor writes history storage.

**Tech Stack:** Swift 6, XCTest, SwiftUI, SwiftPM, Xcode.

---

## File structure

- Modify `readless/Core/ReadingModels.swift`: add the Core display model with a fixed 160-character limit and ellipsis summary to an existing SwiftPM source file.
- Create `Tests/ReadlessCoreTests/RecentReadingTextPresentationTests.swift`: behavioral tests for short, boundary, and long Unicode text.
- Modify `readless/MainWindowView.swift`: render each card from the presentation model, track expanded IDs in view state, and animate its text-height transition.
- Modify `progress.md`: capture task scope, tests/build evidence, manual-test requirement, risk, and rollback point after verification.

### Task 1: Define the Core text-presentation contract with tests

**Files:**
- Create: `Tests/ReadlessCoreTests/RecentReadingTextPresentationTests.swift`
- Modify: `readless/Core/ReadingModels.swift:38-58`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ReadlessCore

final class RecentReadingTextPresentationTests: XCTestCase {
    func testShortTextIsNotCollapsibleAndKeepsFullText() {
        let presentation = RecentReadingTextPresentation(text: "短文本")

        XCTAssertFalse(presentation.isCollapsible)
        XCTAssertEqual(presentation.collapsedText, "短文本")
    }

    func testTextAtCharacterLimitIsNotCollapsible() {
        let text = String(repeating: "阅", count: 160)
        let presentation = RecentReadingTextPresentation(text: text)

        XCTAssertFalse(presentation.isCollapsible)
        XCTAssertEqual(presentation.collapsedText, text)
    }

    func testTextBeyondCharacterLimitUsesFirst160CharactersAndEllipsis() {
        let text = String(repeating: "读", count: 161)
        let presentation = RecentReadingTextPresentation(text: text)

        XCTAssertTrue(presentation.isCollapsible)
        XCTAssertEqual(presentation.collapsedText, String(repeating: "读", count: 160) + "…")
    }
}
```

- [ ] **Step 2: Run the tests to verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter RecentReadingTextPresentationTests
```

Expected: compilation fails because `RecentReadingTextPresentation` does not yet exist.

### Task 2: Implement and verify the Core presentation type

**Files:**
- Modify: `readless/Core/ReadingModels.swift:38-58`
- Test: `Tests/ReadlessCoreTests/RecentReadingTextPresentationTests.swift`

- [ ] **Step 1: Write the minimal implementation**

```swift
import Foundation

struct RecentReadingTextPresentation: Equatable, Sendable {
    static let collapsedCharacterLimit = 160

    let fullText: String

    init(text: String) {
        fullText = text
    }

    var isCollapsible: Bool {
        fullText.count > Self.collapsedCharacterLimit
    }

    var collapsedText: String {
        guard isCollapsible else {
            return fullText
        }
        return String(fullText.prefix(Self.collapsedCharacterLimit)) + "…"
    }
}
```

- [ ] **Step 2: Run the focused tests to verify GREEN**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter RecentReadingTextPresentationTests
```

Expected: 3 tests execute with 0 failures.

- [ ] **Step 3: Commit the Core contract**

```bash
git add readless/Core/ReadingModels.swift Tests/ReadlessCoreTests/RecentReadingTextPresentationTests.swift
git commit -m "feat: add recent reading text presentation"
```

### Task 3: Render independent expand/collapse controls

**Files:**
- Modify: `readless/MainWindowView.swift:742-814`

- [ ] **Step 1: Add transient expansion state and card presentation selection**

At the top of `RecentReadingsView`, add:

```swift
@State private var expandedReadingIDs = Set<RecentReading.ID>()
```

Within `ForEach`, before the card layout, create the presentation and expansion flag:

```swift
let presentation = RecentReadingTextPresentation(text: reading.text)
let isExpanded = expandedReadingIDs.contains(reading.id)
```

Replace the existing `Text(reading.text)` with:

```swift
Text(isExpanded ? presentation.fullText : presentation.collapsedText)
    .font(.system(size: 11, weight: .medium))
    .fixedSize(horizontal: false, vertical: true)

if presentation.isCollapsible {
    Button(isExpanded ? "收起" : "查看全部") {
        withAnimation(.easeInOut(duration: 0.2)) {
            if isExpanded {
                expandedReadingIDs.remove(reading.id)
            } else {
                expandedReadingIDs.insert(reading.id)
            }
        }
    }
    .buttonStyle(.plain)
    .font(.system(size: 11, weight: .semibold))
    .foregroundStyle(Color.accentColor)
    .padding(.top, 1)
}
```

- [ ] **Step 2: Animate card height and preserve narrow-width behavior**

Apply the following modifier to each record card, after its `clipShape`:

```swift
.animation(
    .easeInOut(duration: 0.2),
    value: expandedReadingIDs.contains(reading.id)
)
```

Keep the existing `.fixedSize(horizontal: false, vertical: true)` on the text, the fixed-width icon frame, and `Spacer(minLength: 0)`, so text and the inline button wrap instead of squeezing the icon or overflowing narrow windows.

- [ ] **Step 3: Build the complete app**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project readless.xcodeproj -scheme readless -configuration Debug -derivedDataPath /tmp/readless-recent-readings-collapse-derived build CODE_SIGNING_ALLOWED=NO
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit the UI behavior**

```bash
git add readless/MainWindowView.swift
git commit -m "feat: collapse long recent readings"
```

### Task 4: Run the final verification and document evidence

**Files:**
- Modify: `progress.md`

- [ ] **Step 1: Run full Core regression tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test
```

Expected: all tests pass with 0 failures.

- [ ] **Step 2: Check whitespace and review the scoped diff**

```bash
git diff --check HEAD~2..HEAD
git status --short
```

Expected: no `git diff --check` output; status contains only the intended plan/progress documentation changes before the final documentation commit.

- [ ] **Step 3: Update progress evidence**

Append a dated “最近朗读正文折叠与展开” section to `progress.md` that records:

```markdown
## 最近朗读正文折叠与展开（2026-08-12）

- 级别：L1。仅新增 Core 展示辅助、Core 测试和 `MainWindowView` 的会话内状态；未修改朗读历史、权限、快捷键、持久化或工程配置。
- 行为：正文超过 160 字符时默认显示前 160 字符与省略号；每条记录可独立“查看全部”或“收起”，状态不持久化；高度变化使用 0.2 秒 ease-in-out。
- 验证：记录实际运行的 `xcrun swift test` 结果和 Xcode 构建结果；手测列出窄窗口、逐条独立展开/收起和重新打开后默认折叠，若未执行则明确标注。
- 回滚：`git revert <UI提交> <Core提交>`；不会删除或改写已保存的最近朗读记录。
```

- [ ] **Step 4: Commit verification documentation**

```bash
git add progress.md docs/superpowers/plans/2026-08-12-recent-readings-collapse.md
git commit -m "docs: record recent readings collapse verification"
```
