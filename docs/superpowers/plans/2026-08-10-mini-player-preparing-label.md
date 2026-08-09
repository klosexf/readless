# Mini Player Preparing Label Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the mini player's “正在准备” state label immediately readable by using a 13 pt semibold font.

**Architecture:** The presentation-only change stays inside `MiniPlayerView`. A focused SwiftPM source test guards the exact status label modifier without importing AppKit or altering the ReadlessCore target configuration. `progress.md` captures the validation evidence required by the repository guide.

**Tech Stack:** SwiftUI, XCTest, SwiftPM, Xcode command-line build.

---

### Task 1: Guard and apply the preparing-status label style

**Files:**
- Create: `Tests/ReadlessCoreTests/MiniPlayerViewSourceTests.swift`
- Modify: `readless/MiniPlayerView.swift:69-71`
- Modify: `progress.md`

- [ ] **Step 1: Write the failing source-level regression test**

```swift
import Foundation
import XCTest
@testable import ReadlessCore

final class MiniPlayerViewSourceTests: XCTestCase {
    func testPlaybackStatusLabelUsesReadableSemiboldFont() throws {
        let source = try miniPlayerSource()
        let statusSection = try XCTUnwrap(
            source.components(
                separatedBy: "Text(state.playbackState.displayName)"
            ).dropFirst().first?.components(separatedBy: "Slider(").first
        )

        XCTAssertTrue(
            statusSection.contains(
                ".font(.system(size: 13, weight: .semibold))"
            )
        )
    }

    private func miniPlayerSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(
                "readless/MiniPlayerView.swift"
            ),
            encoding: .utf8
        )
    }
}
```

- [ ] **Step 2: Run the focused test and confirm it fails for the current 10 pt font**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache \
xcrun swift test --filter MiniPlayerViewSourceTests
```

Expected: `testPlaybackStatusLabelUsesReadableSemiboldFont` fails because the status label currently has `.font(.system(size: 10))`.

- [ ] **Step 3: Apply the minimum SwiftUI style change**

Replace the status label modifier in `MiniPlayerView.swift`:

```swift
Text(state.playbackState.displayName)
    .font(.system(size: 13, weight: .semibold))
    .foregroundStyle(.secondary)
```

Do not change the label text, surrounding `HStack`, colours, opacity, `Slider`, actions, playback state, accessibility labels, or any other type.

- [ ] **Step 4: Run the focused source test and confirm it passes**

Run the command from Step 2.

Expected: the selected test suite completes with `0 failures`.

- [ ] **Step 5: Run full validation**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache \
xcrun swift test

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project readless.xcodeproj -scheme readless \
-configuration Debug -derivedDataPath /tmp/readless-preparing-label-derived \
build CODE_SIGNING_ALLOWED=NO
```

Expected: `swift test` completes with `0 failures`; the Xcode command ends with `BUILD SUCCEEDED`.

- [ ] **Step 6: Record verification evidence and commit the scoped change**

Append to `progress.md` the chosen 13 pt semibold value, changed files, exact verification commands and outcomes, plus the remaining user hand-test for the preparing state.

```bash
git add readless/MiniPlayerView.swift \
  Tests/ReadlessCoreTests/MiniPlayerViewSourceTests.swift \
  progress.md \
  docs/superpowers/specs/2026-08-10-mini-player-preparing-label-design.md \
  docs/superpowers/plans/2026-08-10-mini-player-preparing-label.md
git commit -m "fix: enlarge mini player preparing label"
```

## Self-review

- **Spec coverage:** Task 1 changes only the approved status label, preserves all explicitly out-of-scope UI and behavioural elements, and writes the required verification record.
- **No placeholders:** The task includes exact files, test code, source replacement, commands and expected outcomes.
- **Type consistency:** The test reads the existing SwiftUI source only; it adds no production APIs, dependencies or target configuration.
