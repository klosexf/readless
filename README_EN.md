<p align="center">
  <img src="./assets/readme/hero.svg" width="100%" alt="readless - macOS menu bar listen-and-read assistant">
</p>

<p align="center">
  <a href="./README.md">中文</a> | English
</p>

---

readless is a native macOS menu bar listen-and-read assistant. Select text in any app, press one hotkey, and within 1.5 seconds you'll hear clean, speed-controllable, cross-app continuous speech playback.

macOS's built-in speech features are buried deep, offer limited playback controls, and URLs or hard line breaks disrupt the listening experience. readless doesn't just "make text speak" — it lets you **listen to an article smoothly, like a podcast**.

## Key Features

- **One-Key Reading** - Select text in any app, press `⌥R` to start; press again to pause/resume; selecting new text auto-replaces
- **Clipboard Reading** - Press `⌥⇧R` to explicitly read clipboard content; never silently falls back on selection failure
- **Text Sanitizing** - Auto-filters standalone URL lines, merges PDF hard line breaks, detects tab-separated tables and reads them naturally
- **Cross-App Continuous Playback** - Switching apps doesn't interrupt reading; mini player doesn't steal keyboard focus
- **Playback Controls** - Progress bar scrubbing, speed adjustment, sentence-level navigation, Esc to stop; supports system media keys and AirPods controls
- **Multiple Voice Providers** - Supports OpenAI, Doubao (Volcano Engine), Alibaba Bailian, and OpenAI-compatible custom endpoints
- **Credential Security** - All API credentials stored in macOS Keychain, never written to config files
- **Recent Readings** - Locally stores up to 3 recent reading records, collapsible, no data uploaded

## How It Works

<p align="center">
  <img src="./assets/readme/workflow.svg" width="100%" alt="readless workflow: select text -> press hotkey -> text sanitizing -> speech synthesis -> mini player playback">
</p>

readless reads the current text selection via the Accessibility API, sanitizes it, sends it to your configured voice provider for synthesis, and plays the audio through a mini player at the bottom of the screen. The entire flow never monitors the clipboard or scans selections in the background — it only reads on hotkey trigger.

## Installation

### 1. Download

Download the latest `.dmg` file from the [Releases](https://github.com/klosexf/readless/releases) page.

### 2. Mount and Install

Double-click the `.dmg` file, then drag the Readless icon into the "Applications" folder.

### 3. First Launch

Since this app is not signed by an Apple Developer, macOS will block it on first launch with a "cannot be opened because the developer cannot be verified" message. Use one of the following methods:

#### Option 1: Right-Click Open (Recommended)

1. Find Readless in "Finder > Applications"
2. **Control-click** the Readless icon (or right-click)
3. Select "Open" from the context menu
4. A dialog will show "cannot verify the developer"; click "Open"

This only needs to be done once; afterwards you can launch normally by double-clicking.

#### Option 2: Allow in System Settings

1. Try double-clicking Readless, then dismiss the block dialog
2. Open "System Settings > Privacy & Security"
3. At the bottom, you'll see "Readless was blocked"; click "Open Anyway"
4. Enter your password to confirm

#### Option 3: Terminal Command (if the above don't work)

```bash
xattr -cr /Applications/Readless.app
```

This removes the app's quarantine attribute. After running, you can open it normally.

> These operations only affect this app and do not change your system security settings. Readless is open source — you can review the code to verify its safety.

### 4. Grant Permissions

When you first use the reading feature, the system will prompt for "Accessibility" permission. Enable Readless in "System Settings > Privacy & Security > Accessibility", otherwise it cannot read selected text.

### Build from Source

```bash
git clone https://github.com/klosexf/readless.git
cd readless
open readless.xcodeproj
```

Select the `readless` scheme in Xcode, then `⌘R` to build and run. Requires macOS 15+ and Xcode 16+.

## Getting Started

After first launch, follow the onboarding guide to complete four steps:

1. **Choose a provider** - Select a voice provider and enter credentials; the dynamic form explains each field
2. **Play a test sentence** - Verify that credentials, network, and voice pipeline work
3. **Accessibility permission** - Grant access so readless can read selections on hotkey trigger
4. **Practice the trigger** - Select the sample text and press `⌥R`; onboarding completes on success

> Accessibility permission is only requested after the voice pipeline is verified, avoiding the "granted but service unavailable" frustration.

## Voice Service Configuration

readless uses a BYOK (Bring Your Own Key) model — it doesn't run its own voice service. The text you choose to read is sent directly to your configured voice provider. Credentials are stored only in macOS Keychain.

| Provider | Required Fields | Notes |
| --- | --- | --- |
| OpenAI | API Key (Base URL customizable) | Supports tts-1 / tts-1-hd models |
| Doubao (Volcano Engine) | App ID, API Key, Cluster | Use the key from "API Key Management" |
| Alibaba Bailian | DashScope API Key, Region | Supports CosyVoice model series |
| OpenAI-compatible | API Key, Base URL | Any service with an OpenAI-compatible API |

When switching providers in "Voice Service Settings", the form dynamically adapts to show only the fields required by that provider.

## Privacy

> No data is uploaded to this project's servers. The text you choose to read is sent to your configured voice provider. Credentials are stored only in macOS Keychain.

- Selected text and clipboard content are used only for the current reading session — never written to logs, test snapshots, or persistent storage
- No remote telemetry, no usage data collection, no app usage tracking
- Recent reading records are purely local (up to 3), can be disabled or cleared at any time
- Accessibility selection failure never auto-falls back to clipboard; clipboard is only read when you explicitly trigger it
- Error messages never contain selection text, clipboard content, or credential fragments

## Tech Stack

| Layer | Technology |
| --- | --- |
| UI | SwiftUI + AppKit |
| Audio | AVFoundation + Cloud TTS API |
| Global Hotkeys | Carbon.HIToolbox |
| Selection Reading | Accessibility API |
| Concurrency | Swift Concurrency (`@MainActor` boundaries) |
| Testing | SwiftPM + XCTest |
| Project | Xcode project (full app) + SwiftPM (core logic) |

### Architecture

```
SwiftUI / AppKit UI Layer
        ↓ actions / published state
AppDelegate + ReadingCoordinator
        ↓ protocols
System Adapters (AX / Clipboard / Speech / Carbon)
```

- **View** only sends actions and observes state — never calls system APIs directly
- **ReadingCoordinator** handles cross-system reading decisions
- **Core** (`readless/Core/`) holds reusable pure logic, tested via SwiftPM
- **System** (`readless/System/`) holds system adapters, injected via protocols

## Development

```bash
# Run core tests
swift test

# Run specific tests
swift test --filter ReadingCoordinatorTests
swift test --filter TextSanitizerTests

# Build SwiftPM core
swift build
```

> `swift test` covers `ReadlessCore` exposed by `Package.swift`. For the full app build, open `readless.xcodeproj` in Xcode.

### Project Structure

```
readless/
├── Package.swift              # ReadlessCore and test definitions
├── Tests/ReadlessCoreTests/   # Core unit tests
├── readless/
│   ├── AppDelegate.swift      # Dependency wiring and runtime bindings
│   ├── AppState.swift         # UI/playback state and user-facing copy
│   ├── Core/                  # Models, protocols, coordinator, pure logic
│   ├── System/                # AX, Carbon, clipboard, speech adapters
│   ├── *View.swift            # SwiftUI views
│   └── *Controller.swift      # AppKit windows and menu bar
├── readless.xcodeproj/        # Full macOS app project
└── assets/readme/             # README visual assets
```

## Compatibility

- Minimum **macOS 15**, targeting Apple Silicon
- macOS 26+ uses system Liquid Glass material; macOS 15–25 uses `NSVisualEffectView` / SwiftUI `Material`
- Both tiers share the same information architecture, window sizes, and interaction logic — only the material implementation differs
- Animations respect the "Reduce Motion" system setting

## Hotkeys

| Hotkey | Action | Description |
| --- | --- | --- |
| `⌥R` | Read Selection | Reads selected text in the current app; press again to pause/resume |
| `⌥⇧R` | Read Clipboard | Reads clipboard content aloud |
| `Esc` | Stop | Stops reading and dismisses the mini player |

> Hotkeys can be customized in Settings. On conflict, the last working configuration is automatically restored.

## Contributing

Issues and Pull Requests are welcome. Please write commit messages in Chinese, following the "type: brief description" format, e.g. `feat: add feature`, `fix: fix issue`.

## License

MIT
