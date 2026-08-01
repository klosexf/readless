# Voice Service Settings Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reformat the native macOS voice-service editor as a reference-matched two-column settings form without changing speech configuration behavior.

**Architecture:** Keep all changes in `VoiceServiceEditor` within `MainWindowView.swift`. A small view helper owns the shared left label column and full-width control column; existing bindings, validation, Keychain behavior, and save/test actions remain untouched. The SwiftPM test target intentionally excludes SwiftUI window code, so verification is an Xcode build plus visual review of both provider states.

**Tech Stack:** Swift 6, SwiftUI, macOS 15, Xcode.

---

## File map

- Modify `readless/MainWindowView.swift`: replace fixed-width `LabeledContent` rows in `VoiceServiceEditor` with a reusable two-column row helper; remove 230 pt control widths; visually separate the privacy/status note and keep the action area aligned.
- Modify `docs/superpowers/specs/2026-08-01-voice-service-settings-layout-design.md`: record the verified build and visual-QA evidence after implementation.

### Task 1: Convert the voice-service editor to a two-column form

**Files:**
- Modify: `readless/MainWindowView.swift:465-579`

- [ ] **Step 1: Record the current SwiftUI build baseline.**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project readless.xcodeproj -scheme readless -configuration Debug \
  -derivedDataPath /tmp/readless-voice-layout-baseline \
  build CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`. If this fails, stop and report the baseline failure before changing source.

- [ ] **Step 2: Replace `LabeledContent` with one reusable label/control row.**

In `VoiceServiceEditor`, add the following helper next to `labeledField` and use it for the provider picker, each normal text field, and the credential field:

```swift
private func serviceFormRow<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
) -> some View {
    HStack(alignment: .center, spacing: 12) {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .frame(width: 92, alignment: .leading)

        content()
            .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: .infinity)
}
```

Render the provider row as:

```swift
serviceFormRow("服务商") {
    Picker("服务商", selection: $provider) {
        Text("豆包（火山引擎）").tag(VoiceProviderKind.doubao)
        Text("OpenAI-compatible").tag(VoiceProviderKind.openAICompatible)
        Text("OpenAI · 即将支持").tag(VoiceProviderKind.openAI)
        Text("阿里百炼 · 即将支持").tag(VoiceProviderKind.alibaba)
    }
    .labelsHidden()
}
```

Change `labeledField` and `credentialField` to call `serviceFormRow`, keeping `.textFieldStyle(.roundedBorder)` but removing every `.frame(width: 230)`.

- [ ] **Step 3: Match the reference hierarchy around the field group.**

Set the editor’s main `VStack` row spacing to `8`. Keep the field group before the privacy copy. Replace the existing green background with the following blue-gray note treatment while retaining the current privacy copy:

```swift
Label(
    "不会经过 Readless 的服务器。发起朗读时，文字会直接发送给你配置的服务商；凭据不会显示或写入偏好设置。",
    systemImage: "info.circle"
)
.font(.system(size: 10))
.foregroundStyle(.secondary)
.frame(maxWidth: .infinity, alignment: .leading)
.padding(12)
.background(Color.accentColor.opacity(0.08))
.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
```

Keep validation errors, “凭据已保存”, the optional test button, and save button in their existing order and with their existing actions. Do not change `save()`, `loadSavedConfiguration()`, provider cases, field bindings, or button disable conditions.

- [ ] **Step 4: Build the edited app.**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project readless.xcodeproj -scheme readless -configuration Debug \
  -derivedDataPath /tmp/readless-voice-layout-build \
  build CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **` with no Swift type-check errors in `VoiceServiceEditor`.

- [ ] **Step 5: Visually verify the two supported provider states.**

Launch the Debug app and inspect the “语音服务” page at the same desktop width used by the reference image.

Verify all of the following:

- The labels share one 92 pt left column and every control begins on the same vertical baseline.
- App ID, credential, Cluster/Model, and voice fields consume the full remaining width without clipping.
- The provider picker, `.doubao` fields, and `.openAICompatible` fields remain selectable and visible.
- The blue-gray privacy note appears beneath the field group, before status and actions.
- Error text, saved status, “播放内置测试句”, and “保存” remain reachable and retain their existing behavior.

- [ ] **Step 6: Commit the isolated implementation.**

```bash
git add readless/MainWindowView.swift \
  docs/superpowers/specs/2026-08-01-voice-service-settings-layout-design.md
git commit -m "feat: refine voice service form layout"
```

### Task 2: Run regression checks and record evidence

**Files:**
- Modify: `docs/superpowers/specs/2026-08-01-voice-service-settings-layout-design.md`

- [ ] **Step 1: Run the Core regression suite.**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache \
xcrun swift test
```

Expected: all existing `ReadlessCoreTests` pass. The suite covers the unchanged configuration validation and persistence contracts.

- [ ] **Step 2: Record the exact verification outcome.**

Append a `## Verification` section to the design specification listing the successful Xcode build, SwiftPM test run, and the provider states visually checked. If any check is blocked, state the specific blocker rather than reporting it as successful.

- [ ] **Step 3: Commit the verification record.**

```bash
git add docs/superpowers/specs/2026-08-01-voice-service-settings-layout-design.md
git commit -m "docs: record voice layout verification"
```
