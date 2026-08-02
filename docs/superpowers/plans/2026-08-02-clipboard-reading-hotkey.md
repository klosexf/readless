# Clipboard Reading Hotkey Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a separately configurable global shortcut that explicitly reads the
clipboard, while preserving the existing selection-reading shortcut and its
privacy behavior.

**Architecture:** Keep `ReadingCoordinator.readClipboard()` as the sole
clipboard-reading workflow. Add a second persisted configuration and a second
`GlobalHotKeyController` in `AppDelegate`; each controller owns a distinct Carbon
identifier and callback. The settings view exposes two source-labelled recorder
controls that update only their corresponding configuration.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Carbon.HIToolbox, UserDefaults,
XCTest, SwiftPM, Xcode.

---

## File map

- Modify `readless/Core/HotKeyConfiguration.swift`: define the clipboard default
  and independent load/save APIs without changing the existing selection key.
- Modify `Tests/ReadlessCoreTests/HotKeyConfigurationTests.swift`: test both
  defaults and independent persistence.
- Modify `readless/AppState.swift`: retain the selection display name, add the
  clipboard display name, and make the conflict wording source-neutral.
- Modify `Tests/ReadlessCoreTests/AppStateTests.swift`: assert the revised
  source-neutral conflict text.
- Modify `readless/System/GlobalHotKeyController.swift`: accept an injected
  Carbon identifier and only dispatch matching events to its action.
- Modify `readless/AppActions.swift`: expose a clipboard-specific shortcut
  update action.
- Modify `readless/AppDelegate.swift`: create, retain, register, and update two
  independent global hotkey controllers.
- Modify `readless/ShortcutRecorderView.swift`: accept a source-specific title.
- Modify `readless/MainWindowView.swift`: show separately labelled selection and
  clipboard shortcut recorders.
- Modify `progress.md`: record the implementation scope and verification
  evidence after code changes.

### Task 1: Extend shortcut configuration with a clipboard-specific preference

**Files:**
- Modify: `readless/Core/HotKeyConfiguration.swift:12-58`
- Test: `Tests/ReadlessCoreTests/HotKeyConfigurationTests.swift:4-33`

- [ ] **Step 1: Write failing default and independent-persistence tests**

  Add tests that establish the new public API and preference isolation:

  ```swift
  func testDefaultClipboardShortcutIsOptionShiftR() {
      let shortcut = HotKeyConfiguration.defaultReadClipboard

      XCTAssertEqual(shortcut.keyCode, 15)
      XCTAssertEqual(shortcut.modifiers, [.option, .shift])
      XCTAssertEqual(shortcut.displayName, "⌥⇧R")
  }

  func testClipboardShortcutRoundTripsWithoutReplacingSelectionShortcut() {
      let suiteName = "ReadlessTests.\(UUID().uuidString)"
      let defaults = UserDefaults(suiteName: suiteName)!
      defer { defaults.removePersistentDomain(forName: suiteName) }
      let store = HotKeyConfigurationStore(defaults: defaults)
      let selection = HotKeyConfiguration(
          keyCode: 1,
          modifiers: [.command, .shift],
          keyLabel: "S"
      )
      let clipboard = HotKeyConfiguration(
          keyCode: 9,
          modifiers: [.option, .shift],
          keyLabel: "V"
      )

      store.save(selection)
      store.saveClipboard(clipboard)

      XCTAssertEqual(store.load(), selection)
      XCTAssertEqual(store.loadClipboard(), clipboard)
  }
  ```

- [ ] **Step 2: Run the focused test to verify the red state**

  Run:

  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter HotKeyConfigurationTests
  ```

  Expected: compilation failure because `defaultReadClipboard`,
  `saveClipboard(_:)`, and `loadClipboard()` do not exist yet.

- [ ] **Step 3: Add the minimum configuration and storage implementation**

  In `HotKeyConfiguration`, add the default:

  ```swift
  static let defaultReadClipboard = Self(
      keyCode: 15,
      modifiers: [.option, .shift],
      keyLabel: "R"
  )
  ```

  In `HotKeyConfigurationStore`, retain the existing `key` value
  `"readSelectionHotKey"`, add `clipboardKey = "readClipboardHotKey"`, and
  add these methods while keeping `load()` and `save(_:)` unchanged:

  ```swift
  func loadClipboard() -> HotKeyConfiguration {
      guard
          let data = defaults.data(forKey: clipboardKey),
          let value = try? JSONDecoder().decode(
              HotKeyConfiguration.self,
              from: data
          )
      else {
          return .defaultReadClipboard
      }
      return value
  }

  func saveClipboard(_ value: HotKeyConfiguration) {
      defaults.set(try? JSONEncoder().encode(value), forKey: clipboardKey)
  }
  ```

- [ ] **Step 4: Run the focused test to verify green**

  Run the command from Step 2.

  Expected: all `HotKeyConfigurationTests` pass.

- [ ] **Step 5: Commit the configuration change**

  ```bash
  git add readless/Core/HotKeyConfiguration.swift Tests/ReadlessCoreTests/HotKeyConfigurationTests.swift
  git commit -m "feat: persist clipboard reading hotkey"
  ```

### Task 2: Make conflict feedback source-neutral

**Files:**
- Modify: `readless/AppState.swift:22-53`
- Test: `Tests/ReadlessCoreTests/AppStateTests.swift:150-165`

- [ ] **Step 1: Update the existing user-message expectation to a generic conflict message**

  Replace the `.hotKeyConflict` assertion with:

  ```swift
  XCTAssertEqual(
      ReadingError.hotKeyConflict.userMessage,
      "快捷键已被占用，请设置新的快捷键。"
  )
  ```

- [ ] **Step 2: Run the focused test to verify red**

  Run:

  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter AppStateTests
  ```

  Expected: one failure showing the old `⌥R`-specific message.

- [ ] **Step 3: Replace the `.hotKeyConflict` user message**

  In `ReadingError.userMessage`, replace the hard-coded selection shortcut text:

  ```swift
  case .hotKeyConflict:
      "⌥R 已被占用，请设置新的快捷键。"
  ```

  with:

  ```swift
  case .hotKeyConflict:
      "快捷键已被占用，请设置新的快捷键。"
  ```

- [ ] **Step 4: Run the focused test to verify green**

  Run the command from Step 2.

  Expected: all `AppStateTests` pass.

- [ ] **Step 5: Commit the error-message adjustment**

  ```bash
  git add readless/AppState.swift Tests/ReadlessCoreTests/AppStateTests.swift
  git commit -m "fix: generalize hotkey conflict message"
  ```

### Task 3: Route independently identified Carbon hotkeys

**Files:**
- Modify: `readless/System/GlobalHotKeyController.swift:4-147`

- [ ] **Step 1: Change the controller initializer to require an event identifier**

  Replace the fixed `private static let identifier: UInt32 = 1` with an instance
  property and require the identifier at construction:

  ```swift
  private static let signature: OSType = 0x52444C53

  private let identifier: UInt32
  private var hotKeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?
  private let action: () -> Void

  init(identifier: UInt32, action: @escaping () -> Void) {
      self.identifier = identifier
      self.action = action
      installEventHandler()
  }
  ```

- [ ] **Step 2: Use the instance identifier in registration and filtering**

  In `register(_:)`, create `EventHotKeyID` with `id: identifier`. In
  `handle(_:)`, compare `identifier.id == self.identifier`. Leave the existing
  signature check, event handler installation/removal, and `unregister()`
  lifecycle unchanged.

- [ ] **Step 3: Build the full app to verify Carbon compilation**

  Run:

  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project readless.xcodeproj -scheme readless -configuration Debug -derivedDataPath /tmp/readless-clipboard-hotkey-derived build CODE_SIGNING_ALLOWED=NO
  ```

  Expected: `BUILD SUCCEEDED`. SwiftPM excludes the System directory, so it
  cannot validate this controller.

- [ ] **Step 4: Commit the controller identity change**

  ```bash
  git add readless/System/GlobalHotKeyController.swift
  git commit -m "feat: support distinct global hotkey identifiers"
  ```

### Task 4: Register and update the clipboard shortcut independently

**Files:**
- Modify: `readless/AppState.swift:99-109`
- Modify: `readless/AppActions.swift:3-11`
- Modify: `readless/AppDelegate.swift:4-191`

- [ ] **Step 1: Add the clipboard display name and action API**

  Add this state property next to `hotKeyDisplayName`:

  ```swift
  @Published var clipboardHotKeyDisplayName = "⌥⇧R"
  ```

  Add this `ReadlessActions` property next to `updateHotKey`:

  ```swift
  let updateClipboardHotKey: (HotKeyConfiguration) -> Void
  ```

  Update every `ReadlessActions(...)` construction, including preview fixtures,
  with an explicit no-op or runtime closure for the new property.

- [ ] **Step 2: Add the second controller and callback in `AppDelegate`**

  Keep `hotKeyController` as the selection controller and add:

  ```swift
  private var clipboardHotKeyController: GlobalHotKeyController?
  ```

  Construct the two controllers with separate IDs:

  ```swift
  let hotKeyController = GlobalHotKeyController(identifier: 1) {
      coordinator.handleReadShortcut()
  }
  let clipboardHotKeyController = GlobalHotKeyController(identifier: 2) {
      coordinator.readClipboard()
  }
  ```

  Store both properties before calling registration. Replace
  `registerSavedHotKey()` with `registerSavedHotKeys()`, which loads and
  registers each configuration independently and sets both display names. The
  selection registration continues to call `state.showFailure(error)` on failure;
  the clipboard registration does the same without unregistering selection.

- [ ] **Step 3: Add a clipboard-only update method**

  Add `updateClipboardHotKey(_:)`, mirroring `updateHotKey(_:)` but using
  `clipboardHotKeyController`, `hotKeyStore.loadClipboard()`,
  `hotKeyStore.saveClipboard(_:)`, and `state.clipboardHotKeyDisplayName`.
  On registration failure, re-register only the old clipboard configuration,
  restore only its displayed name, and present `.hotKeyConflict` with the same
  interrupting/non-interrupting state logic as the selection update method.

  Wire it into the runtime action set:

  ```swift
  updateClipboardHotKey: { [weak self] configuration in
      self?.updateClipboardHotKey(configuration)
  },
  ```

- [ ] **Step 4: Build the full app**

  Run the Task 3 build command.

  Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit runtime integration**

  ```bash
  git add readless/AppState.swift readless/AppActions.swift readless/AppDelegate.swift readless/PreviewFixtures.swift
  git commit -m "feat: register clipboard reading hotkey"
  ```

### Task 5: Show two source-specific shortcut controls

**Files:**
- Modify: `readless/ShortcutRecorderView.swift:3-57`
- Modify: `readless/MainWindowView.swift:104-161`

- [ ] **Step 1: Make the recorder title configurable**

  Change the public view interface to accept a title and render it instead of
  the hard-coded `"触发快捷键"`:

  ```swift
  struct ShortcutRecorderView: View {
      let title: String
      let displayName: String
      let onRecorded: (HotKeyConfiguration) -> Void
      let onRestoreDefault: () -> Void

      var body: some View {
          VStack(alignment: .leading, spacing: 10) {
              Text(title)
                  .font(.system(size: 12, weight: .semibold))
              // Preserve the existing recorder button and cancel behavior.
          }
      }
  }
  ```

- [ ] **Step 2: Replace the single recorder with two explicit controls**

  In `CurrentPlaybackView`, keep the existing selection configuration but label
  it `"选区朗读快捷键"`. Add a second recorder immediately below it:

  ```swift
  ShortcutRecorderView(
      title: "剪贴板朗读快捷键",
      displayName: state.clipboardHotKeyDisplayName,
      onRecorded: actions.updateClipboardHotKey,
      onRestoreDefault: {
          actions.updateClipboardHotKey(.defaultReadClipboard)
      }
  )
  ```

  Change the helper text to state both actions explicitly:

  ```swift
  Text("选中文字后按选区快捷键；复制文字后按剪贴板快捷键。")
  ```

- [ ] **Step 3: Build the full app and inspect the changed diff**

  Run:

  ```bash
  git diff --check
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project readless.xcodeproj -scheme readless -configuration Debug -derivedDataPath /tmp/readless-clipboard-hotkey-derived build CODE_SIGNING_ALLOWED=NO
  ```

  Expected: no `git diff --check` output and `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit the settings UI**

  Before staging, inspect `git diff -- readless/MainWindowView.swift` because
  the working tree already contains unrelated user edits in that file. Stage
  only the shortcut-settings hunk; do not stage or overwrite the unrelated
  changes.

  ```bash
  git add -p readless/ShortcutRecorderView.swift readless/MainWindowView.swift
  git commit -m "feat: configure clipboard reading hotkey"
  ```

### Task 6: Run regression, build, and manual system verification

**Files:**
- Modify: `progress.md`

- [ ] **Step 1: Run the complete SwiftPM suite**

  Run:

  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test
  ```

  Expected: all tests pass with zero failures.

- [ ] **Step 2: Run a fresh full-app build**

  Run the Task 3 build command after all implementation changes.

  Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Manually verify both global shortcuts**

  In a normally installed/signable app with a configured voice provider:

  1. Select text in a supported app, press `⌥R`, and confirm selection reading
     starts without reading the clipboard.
  2. Copy different text with `⌘C`, press `⌥⇧R`, and confirm only the copied
     text starts reading.
  3. Set the clipboard to no text, press `⌥⇧R` while speech is playing, and
     confirm the current session remains playing and the empty-clipboard error
     is displayed.
  4. Change the clipboard shortcut in settings, confirm the new key works and
     `⌥⇧R` no longer triggers clipboard reading; restore its default.
  5. Attempt to configure the clipboard shortcut to an occupied key, confirm
     the generic conflict message appears and its prior working configuration
     still functions.

- [ ] **Step 4: Record evidence and commit the progress entry**

  Update `progress.md` with the date, the full test and build commands and
  their results, plus each completed manual-check result or any concrete
  blocker. Do not record clipboard contents, selected text, credentials, or
  screenshots containing either text source.

  ```bash
  git add progress.md
  git commit -m "docs: record clipboard hotkey verification"
  ```
