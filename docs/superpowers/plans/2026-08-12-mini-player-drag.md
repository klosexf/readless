# Mini Player Background Drag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the mini player be moved from its empty background while preserving its user-selected position through layout refreshes.

**Architecture:** Keep the behaviour in `MiniPlayerPanelController`, where the `NSPanel` is created and resized. Enable AppKit's background-drag support, then distinguish initial centering from later size-only frame updates so state changes do not overwrite a manual position. A source-level XCTest guards this AppKit-only code without adding it to the SwiftPM core target.

**Tech Stack:** AppKit, SwiftUI hosting, XCTest, SwiftPM, Xcode command-line build.

---

### Task 1: Guard and add the panel dragging behaviour

**Files:**
- Modify: `Tests/ReadlessCoreTests/MiniPlayerViewSourceTests.swift`
- Modify: `readless/MiniPlayerPanelController.swift:18-88`
- Modify: `progress.md`

- [ ] **Step 1: Write the failing source-level regression test**

Append this test and helper to `MiniPlayerViewSourceTests`:

```swift
func testMiniPlayerPanelUsesBackgroundDraggingAndPreservesPosition() throws {
    let source = try miniPlayerPanelControllerSource()

    XCTAssertTrue(
        source.contains("panel.isMovableByWindowBackground = true")
    )
    XCTAssertTrue(source.contains("private var hasInitialPosition = false"))
    XCTAssertTrue(
        source.contains(
            "if hasInitialPosition {\n            panel.setFrame("
        )
    )
    XCTAssertFalse(
        source.components(separatedBy: "if hasInitialPosition")
            .dropFirst()
            .joined(separator: "if hasInitialPosition")
            .contains("visibleFrame.midX")
    )
}

private func miniPlayerPanelControllerSource() throws -> String {
    try String(
        contentsOf: try repositoryRoot().appendingPathComponent(
            "readless/MiniPlayerPanelController.swift"
        ),
        encoding: .utf8
    )
}

private func repositoryRoot() throws -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
```

Update the existing `miniPlayerSource()` helper to call `repositoryRoot()`.

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache \
xcrun swift test --filter MiniPlayerViewSourceTests
```

Expected: `testMiniPlayerPanelUsesBackgroundDraggingAndPreservesPosition` fails because the panel lacks background dragging and every layout calculates a centered origin.

- [ ] **Step 3: Apply the minimum AppKit implementation**

In `MiniPlayerPanelController`, add `private var hasInitialPosition = false` below `state`; set `panel.isMovableByWindowBackground = true` with the existing panel configuration; and replace the positioning body with:

```swift
let frame: NSRect
if hasInitialPosition {
    frame = NSRect(origin: panel.frame.origin, size: size)
} else {
    let visibleFrame = panel.screen?.visibleFrame
        ?? NSScreen.main?.visibleFrame
        ?? .zero
    frame = NSRect(
        x: visibleFrame.midX - size.width / 2,
        y: visibleFrame.minY + 24,
        width: size.width,
        height: size.height
    )
    hasInitialPosition = true
}
panel.setFrame(frame, display: true, animate: animated)
```

Do not alter the panel's style mask, level, collection behaviour, activation behaviour, or any playback action.

- [ ] **Step 4: Run the focused test to verify it passes**

Run the command from Step 2.

Expected: `MiniPlayerViewSourceTests` completes with `0 failures`.

- [ ] **Step 5: Run full automated verification**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache \
xcrun swift test

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project readless.xcodeproj -scheme readless \
-configuration Debug -derivedDataPath /tmp/readless-mini-player-drag-derived \
build CODE_SIGNING_ALLOWED=NO
```

Expected: SwiftPM reports `0 failures`; Xcode ends with `BUILD SUCCEEDED`.

- [ ] **Step 6: Record evidence**

Append the completed task to `progress.md`, including the selected background-only drag behaviour, changed files, command outputs, and the remaining user hand-test for empty-space dragging, control clicks, nonactivation, and layout refresh position retention.

## Self-review

- **Spec coverage:** The task enables only background dragging and protects the user-selected position through layout updates; all panel and playback constraints remain untouched.
- **No placeholders:** The task defines exact files, test assertions, implementation code, commands, and expected outputs.
- **Type consistency:** `hasInitialPosition` is declared and used solely by `resizeAndPosition`; the test reads production source without changing target configuration.
