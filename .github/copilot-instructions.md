# Whisper — Copilot Instructions

## Architecture Overview

Whisper is a **speech-to-text dictation app** powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit). It runs on **macOS** (menu-bar utility) and **iOS** (app + custom keyboard extension). The codebase uses two build systems:

- **Swift Package Manager** (`Package.swift`) — builds the macOS executable (`Whisper`) and the shared library (`WhisperShared`)
- **XcodeGen** (`project.yml`) — generates `Whisper.xcodeproj` for the iOS app (`WhisperiOS`) and keyboard extension (`WhisperKeyboard`)

### Key Targets & Layers

| Target            | Path              | Purpose                                                                                                                       |
| ----------------- | ----------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `WhisperShared`   | `Sources/Shared/` | Core library: audio capture, transcription, voice memos, correction engine, vocabulary, design system. Shared by all targets. |
| `Whisper` (macOS) | `Sources/MacApp/` | Menu-bar app. Uses `HotKey` for global shortcuts, `TextInjector` for typing/pasting into other apps via Accessibility APIs.   |
| `WhisperiOS`      | `iOS/App/`        | iOS companion app with `DictationViewModel` driving `ContentView`.                                                            |
| `WhisperKeyboard` | `iOS/Keyboard/`   | Custom keyboard extension that inserts transcribed text via `textDocumentProxy`. Uses `tiny.en` model for speed.              |
| `WhisperTests`    | `Tests/`          | Unit tests against `WhisperShared`.                                                                                           |

### Data Flow

1. `AudioCapture` records mic → converts to 16kHz mono PCM float
2. `Transcriber` runs WhisperKit inference → returns `TranscriptionPayload` (text + word-level timestamps)
3. `CorrectionEngine.shared.apply(to:)` applies learned corrections
4. **macOS**: `TextInjector` types/pastes into the frontmost app. **iOS keyboard**: `textDocumentProxy.insertText()`

## Build & Run

```sh
# macOS — build and run (ALWAYS use --reset-permissions)
./build.sh --reset-permissions && open Whisper.app

# iOS — generate Xcode project then build
xcodegen generate              # reads project.yml → Whisper.xcodeproj
xcodebuild -scheme WhisperiOS -destination 'platform=iOS Simulator,name=iPhone 16' build

# Tests
swift test                     # runs WhisperTests target
```

The iOS target requires **iOS 26.0+** deployment target and uses bundle ID `com.quincy.whisper.ios`. The keyboard extension uses `com.quincy.whisper.ios.keyboard`.

## Project Conventions

### Shared Singletons & Persistence

Core services use the singleton pattern (`CorrectionEngine.shared`, `DictationHistory.shared`, `Vocabulary.shared`, `VoiceMemoStore.shared`). All persist JSON files under `SharedStorage.baseDirectory()/Whisper/`:

- `corrections.json`, `dictation-history.json`, `vocabulary.json`, `voice-memos.json`

On iOS, set `SharedStorage.appGroupID` before accessing storage (see `KeyboardViewController.viewDidLoad`).

### Callback Pattern

`AudioCapture` and `Transcriber` use closure callbacks (`onError`, `onLevel`, `onModelLoaded`) rather than Combine or async sequences. Wire them up in a `setupCallbacks()` method.

### Design System

Use `DesignSystem` constants from `Sources/Shared/DesignSystem.swift`:

- `.backgroundGradient` (dark purple/blue), `.accentGradient` (purple→blue), `.glassCard()` modifier
- iOS views replicate this manually (see `ContentView.swift` background gradient)

### Text Injection (macOS only)

`TextInjector` in `Sources/MacApp/TextInjector.swift` supports three strategies:

1. **AX insert** — preferred for VS Code and similar apps (`insertIntoFocusedElementAdvanced`)
2. **Paste** — `Cmd+V` with clipboard save/restore
3. **Type** — character-by-character CGEvent posting

Target-specific routing uses `shouldForceAXInsertForTarget()` / `shouldForcePasteForTarget()`.

### AI Integration — Copilot Bridge

`tools/copilot-bridge/` is a local Node HTTP service that calls GitHub Copilot for theme analysis of transcribed text. The Swift client is `CopilotBridgeClient` in `ThemesAnalyzer.swift`. Fallback: `KeywordThemesAnalyzer` does local frequency-based analysis. Always code with this fallback pattern — AI features must degrade gracefully.

### Vocabulary System

`Vocabulary` (`Sources/Shared/Vocabulary.swift`) ships with rich domain-specific presets (Software Engineering, Hip-Hop, Houston/Texas, Louisiana/NOLA, Track & Field, etc.). Terms feed into the WhisperKit prompt to improve recognition of jargon. Use `Vocabulary.shared.generatePrompt()` to build the prompt string.

## Testing

Tests live in `Tests/` and target `WhisperShared`. Use temp directories for store tests (see `VoiceMemoStoreTests` which creates an isolated `VoiceMemoStore` via `makeInDirectory`). Audio/transcription tests are not present — the model requires runtime resources.

## Key Dependencies

| Dependency                                                     | Usage                                  |
| -------------------------------------------------------------- | -------------------------------------- |
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) (≥0.9.0) | On-device speech-to-text inference     |
| [HotKey](https://github.com/soffes/HotKey) (≥0.2.0)            | Global keyboard shortcuts (macOS only) |

## Things to Know

- The macOS app is a **menu-bar only** app (`NSStatusItem`). The main UI window opens on demand.
- Audio must be ≥0.5s (8000 samples at 16kHz) or transcription is skipped.
- `Transcriber.cleanTranscription()` filters WhisperKit hallucination artifacts like `[BLANK_AUDIO]`, `Thank you.`, etc.
- The keyboard extension uses the `tiny.en` model; the macOS/iOS app defaults to `base.en`.
- `recordingMode` supports `"hold"` (push-to-talk) and `"toggle"` modes.
- Auto-stop detects silence via `autoStopSilenceSeconds` (default 1.5s) when audio level drops below threshold.
- **Always build with `--reset-permissions`**. Without it, stale TCC grants from previous builds break Accessibility-based text injection. Manually fixing this requires quitting the app, navigating to System Settings > Privacy & Security > Accessibility, removing the old entry, relaunching, and re-approving — the flag automates all of that via `tccutil reset`.
