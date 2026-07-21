# Whisper v2 Bootstrap Context

## Status
- Created on 2026-03-18 in a dedicated git worktree.
- Workspace path: `/Users/quincyobeng/Documents/AI/Claude/Voice-v2`
- Branch: `codex/whisper-v2`
- Source repo: `/Users/quincyobeng/Documents/AI/Claude/Voice`
- Source commit for this workspace: `5d248fc`
- Important: the original workspace had local staged changes on `main` when this worktree was created. Those uncommitted changes were not carried into this v2 worktree.

## Purpose
This file is the temporary single-source briefing for Whisper v2 during implementation. It captures:
- the current repo shape
- the current architecture constraints
- the v2 scope lock
- the execution plan
- the sub-agent operating model

## Current Repo Snapshot
- Project type: Swift package plus Xcode project
- Platforms in `Package.swift`: macOS 14 and iOS 17
- Primary dependencies:
  - `WhisperKit` from `argmaxinc/WhisperKit`
  - `HotKey`
- Top-level structure:
  - `Sources/MacApp`
  - `Sources/Shared`
  - `Tests`
  - `iOS/App`
  - `iOS/Keyboard`
  - `tools/copilot-bridge`

## Current Architecture Notes
Observed from the current codebase before v2 work starts:

- `Sources/MacApp/WhisperApp.swift`
  - App entry is still centered on `AppDelegate`.
  - `AppDelegate` directly orchestrates hotkeys, menu bar state, windows, permissions, audio capture, transcription, insertion, and memo flows.
  - The app currently creates separate `Transcriber` instances for dictation and voice memos.
  - Settings are spread across many raw `@AppStorage` values.

- `Sources/MacApp/MainView.swift`
  - Current main surface is a broader dashboard-style UI.
  - It includes dictation, memos, history, stats/themes, vocabulary, and Copilot/bridge analysis concepts.
  - This confirms the repo has a larger product surface than the intended v2 scope.

- `Sources/Shared/Transcriber.swift`
  - Current transcription abstraction is a thin `WhisperKit` wrapper.
  - It loads one model name directly, transcribes full audio arrays, and prints diagnostics.
  - There is no shared engine actor, no typed dictation session model, and no explicit streaming session contract at this layer.

- `Sources/Shared/VoiceMemoStore.swift`
  - Voice memos are currently persisted to JSON.
  - This aligns with the need for a SQLite migration path in v2.

## Known Current/Product Mismatch Driving v2
These repo traits are the reason v2 needs a tighter architecture:
- direct `AppDelegate` orchestration is too broad
- multiple transcription entry points exist instead of one shared engine
- product scope is wider than `dictation + memos + history/corrections`
- settings are loosely typed
- JSON persistence is still in use
- insertion and app-routing logic need stronger contracts and fallback behavior

## Whisper v2 Objective
Rebuild Whisper v2 as a macOS-only, offline-first dictation app with voice memos, centered on one shared prewarmed transcription engine, streaming partial results, reliable text insertion, and a smaller product surface.

Deferred from v2 core:
- dashboard / smart feed
- design gallery
- Copilot bridge analysis
- themes
- transcript-cleanup UI
- generic file-import transcription UI
- iOS feature work

## Scope Lock
In scope:
- Dictation
- Voice Memos
- History and Corrections
- Local vocabulary
- Learned corrections
- SQLite-backed persistence
- JSON-to-SQLite migration
- Observability and performance work required to hit v2 targets

Out of scope:
- Dashboard / Smart Feed
- Design Gallery
- Copilot bridge analysis
- Themes
- Transcript-cleanup UI
- Generic file-import UI
- iOS feature work

## Contract Freeze
These interfaces should be frozen first and treated as shared contracts:
- `WhisperEngine`
- `DictationSessionState`
- `DictationSessionUpdate`
- `DictationCoordinator`
- `MemoCoordinator`
- `TextInsertionService`
- `SettingsStore`
- `ModelProfile`
- `HistoryRepository`
- `MemoRepository`
- `VocabularyRepository`
- `CorrectionRepository`
- `MigrationRepository`

Phase 0 file map:
- Contracts: `Sources/Shared/V2Contracts.swift`
- Typed settings and model profiles: `Sources/Shared/V2Settings.swift`
- Deterministic prompt builder: `Sources/Shared/V2Prompting.swift`
- Metrics vocabulary: `Sources/Shared/V2Metrics.swift`
- Scripted fake engine: `Sources/Shared/FakeWhisperEngine.swift`
- Phase 0 tests:
  - `Tests/V2SettingsTests.swift`
  - `Tests/V2PromptBuilderTests.swift`
  - `Tests/FakeWhisperEngineTests.swift`

Phase 1 file map:
- Live engine wrapper: `Sources/Shared/LiveWhisperEngine.swift`
- Dictation coordinator: `Sources/Shared/DefaultDictationCoordinator.swift`
- Default deterministic prompt provider: `Sources/Shared/DefaultTranscriptionPromptProvider.swift`
- Additive prompt/correction bridge:
  - `Sources/Shared/CorrectionEngine.swift`
- Phase 1 tests:
  - `Tests/DefaultDictationCoordinatorTests.swift`
  - `Tests/DefaultTranscriptionPromptProviderTests.swift`

Phase 1 insertion slice file map:
- App-profile catalog: `Sources/Shared/InsertionAppProfileCatalog.swift`
- Ordered insertion service: `Sources/Shared/DefaultTextInsertionService.swift`
- macOS runtime adapter: `Sources/MacApp/SystemTextInsertionService.swift`
- Non-blocking injector helpers:
  - `Sources/MacApp/TextInjector.swift`
- App/runtime wiring:
  - `Sources/MacApp/WhisperApp.swift`
  - `Sources/MacApp/HistoryView.swift`
- Phase 1 insertion tests:
  - `Tests/InsertionAppProfileCatalogTests.swift`
  - `Tests/DefaultTextInsertionServiceTests.swift`

Current verification snapshot:
- `swift test` passes with 212 tests green after the insertion slice.

Phase 2 dictation runtime bridge file map:
- Legacy settings bridge for v2 coordinator/profile loading:
  - `Sources/Shared/LegacyAppPreferencesSettingsStore.swift`
- Shared engine compatibility hook:
  - `Sources/Shared/LiveWhisperEngine.swift`
- App runtime migrated from legacy audio/transcriber path to coordinator-driven dictation:
  - `Sources/MacApp/WhisperApp.swift`
- Phase 2 tests:
  - `Tests/LegacyAppPreferencesSettingsStoreTests.swift`

Updated verification snapshot:
- `swift test` passes with 216 tests green after the coordinator/runtime bridge slice.

Phase 3 memo shared-engine slice file map:
- Shared-engine memo manager migration:
  - `Sources/Shared/VoiceMemoManager.swift`
- App runtime wiring to shared engine prompt/settings path:
  - `Sources/MacApp/WhisperApp.swift`
- Phase 3 tests:
  - `Tests/VoiceMemoManagerTests.swift`

Phase 4 persistence and migration slice file map:
- SQLite/GRDB persistence core:
  - `Sources/Shared/SQLiteV2Store.swift`
  - `Sources/Shared/SQLiteRepositoryStore.swift`
- Existing singleton bridges moved off JSON writes and onto SQLite:
  - `Sources/Shared/DictationHistory.swift`
  - `Sources/Shared/VoiceMemoStore.swift`
  - `Sources/Shared/Vocabulary.swift`
  - `Sources/Shared/CorrectionEngine.swift`
- Package dependency update:
  - `Package.swift`
- Phase 4 tests:
  - `Tests/SQLiteRepositoryStoreTests.swift`

Phase 4 UI simplification slice file map:
- Main window reduced to dictation, memos, history, and accuracy controls:
  - `Sources/MacApp/MainView.swift`
- Settings moved to profile-first model selection with advanced raw override only:
  - `Sources/MacApp/SettingsView.swift`
- Shared model-profile descriptions and legacy mapping exposure:
  - `Sources/Shared/V2Settings.swift`
  - `Sources/Shared/LegacyAppPreferencesSettingsStore.swift`

Current verification snapshot:
- `swift test` passes with 221 tests green after persistence, migration import, and UI simplification.
- Manual smoke: `swift run Whisper` launched successfully, completed startup, registered both hotkeys, and reached the normal accessibility-request path before being stopped manually.

Phase 5 history/corrections, cleanup, and observability slice file map:
- History and learned-corrections surface:
  - `Sources/MacApp/HistoryView.swift`
- Learned-correction query/delete support:
  - `Sources/Shared/CorrectionEngine.swift`
- Structured logging and signpost-backed metrics:
  - `Sources/Shared/WhisperTelemetry.swift`
- Runtime measurement/logging integration:
  - `Sources/MacApp/WhisperApp.swift`
  - `Sources/Shared/VoiceMemoManager.swift`
  - `Sources/Shared/AudioCapture.swift`
  - `Sources/Shared/Transcriber.swift`
- Deferred v2 code removed from the tree:
  - `Sources/MacApp/TranscriptCleanupView.swift`
  - `Sources/Shared/ThemesAnalyzer.swift`
  - `Sources/Shared/TranscriptCleanupService.swift`
- Phase 5 tests:
  - `Tests/CorrectionEngineTests.swift`
  - `Tests/WhisperTelemetryTests.swift`

Design asset pass:
- Logo brief:
  - `Design/WHISPER_V2_LOGO_BRIEF.md`
- App icon concept:
  - `Design/WhisperV2-AppIcon.svg`
- Horizontal logo lockup:
  - `Design/WhisperV2-Logo.svg`
- Reproducible export script:
  - `Design/export_app_icon_assets.sh`
- Generated macOS iconset source:
  - `Design/Generated/WhisperV2.iconset`
- Generated macOS icns:
  - `Design/Generated/WhisperV2.icns`
- Modern macOS build wrapper:
  - `build.sh`
- Xcode mac build helper:
  - `scripts/build_xcode_mac.sh`
- Repo-local Xcode build output:
  - `.xcode-build/Build/Products/Debug/Whisper.app`
- macOS Xcode target metadata:
  - `project.yml`
  - `macOS/App/Info.plist`
  - `Whisper.xcodeproj`
- Integrated iOS app icon catalog:
  - `iOS/App/Assets.xcassets/AppIcon.appiconset`

Latest verification snapshot:
- `swift test` passes with 188 tests green after the history/corrections, telemetry, and design handoff pass.
- Manual smoke: `swift run Whisper` stayed running through an 8-second startup smoke window after the telemetry integration.
- SVG logo assets rendered successfully through macOS Quick Look for visual verification.
- The iOS app icon catalog was regenerated successfully from `Design/WhisperV2-AppIcon.svg`.
- `build.sh --no-reset-permissions --no-launch` now builds the app through the `WhisperMac` Xcode target and resolves the bundle at `.xcode-build/Build/Products/Debug/Whisper.app`.
- `./scripts/build_xcode_mac.sh` succeeds with repo-local `.xcode-build` and `.xcode-sourcepackages` directories.

Key overnight outcomes:
- Voice memos now reuse the shared engine path instead of the legacy `Transcriber` path.
- v2 persistence is now SQLite-backed via GRDB, with initial import from:
  - `dictation-history.json`
  - `voice-memos.json`
  - `vocabulary.json`
  - `corrections.json`
- Legacy JSON files are left untouched during import.
- Main window no longer exposes the broader dashboard/Copilot analysis surface.
- Settings now present `Fast`, `Balanced`, `Accurate`, and `Multilingual` as the standard model-selection UI.
- Raw model override remains available only in an advanced/debug disclosure.
- History now includes a first-class learned-corrections surface with search, delete, copy, and clear actions.
- The deferred transcript-cleanup/themes analysis code was removed from the v2 tree to keep the shipped surface aligned with scope.
- Runtime logging now uses `Logger`, and latency/throughput metrics are recorded through `WhisperTelemetry` with `OSSignposter` event hooks.
- A logo direction now exists for v2, and it is directly derived from the app's ASCII waveform, scan-beam, and warm fire-palette motifs.
- The new logo is now wired into the iOS app icon catalog, and the macOS pipeline now targets a generated `.iconset` plus `.icns` for bundle packaging.
- A real `WhisperMac` macOS application target now exists in the Xcode project; stable CLI builds use repo-local `.xcode-build` and `.xcode-sourcepackages` paths.
- The old repo-root manual `swift build` app assembly path has been retired in favor of the Xcode-produced macOS app bundle.

Behavioral decisions frozen up front:
- One shared `WhisperKit` instance for the whole app
- Launch-time predownload and prewarm of the default profile without blocking on microphone permission
- Streaming dictation uses partial and final updates
- Memo and long-form transcription use VAD chunking
- Prompt construction is deterministic from enabled vocabulary and learned corrections
- Insertion order is `AX insert -> paste with clipboard preservation -> character typing`
- Typing is last-resort fallback for short text only
- User-facing model profiles:
  - `Fast -> tiny.en`
  - `Balanced -> base.en`
  - `Accurate -> small.en`
  - `Multilingual -> base`

Contract correction after initial freeze:
- `WhisperEngine` now includes explicit `stopDictation(sessionID:)` so streaming sessions can be ended without leaking concrete engine types into coordinators.

## Execution Plan
### Phase 0: Freeze contracts and harnesses
- Add baseline metrics
- Add fake engine and fake audio seams
- Add benchmark/regression harnesses
- Add typed settings and model-profile management

### Phase 1: Parallel build after contract freeze
- Build `WhisperEngine`
- Build `TextInsertionService`
- Build SQLite repositories and migration layer
- Reduce UI shell to v2 surfaces

### Phase 2: Dictation MVP integration
- Wire shared engine into dictation coordinator
- Emit partial and final session updates
- Insert final text through ordered insertion strategies
- Persist dictation history

### Phase 3: Memo integration
- Move memo recording/transcription onto shared engine queue
- Persist memo metadata, transcript text, and timings
- Keep audio files on disk as `m4a`

### Phase 4: Migration, cleanup, and performance
- Import existing JSON data into SQLite
- Verify parity before deleting or disabling old paths
- Remove obsolete v2-deferred UI wiring
- Benchmark against current behavior
- Evaluate `whisper.cpp` only if targets still miss after engine refactor

## Workstreams
### Integrator
Owns:
- contract freeze
- cross-workstream decisions
- merge order
- final integration
- acceptance and performance signoff

### Foundation and Harness
Owns:
- fake engine
- fake audio inputs
- metrics vocabulary
- signpost/logging scaffolding
- typed settings and profile mapping
- regression harness

### Engine and Audio
Owns:
- `WhisperEngine`
- `WhisperKit` lifecycle
- predownload/prewarm
- streaming dictation path
- VAD path for memo/long-form transcription

### Dictation Orchestration
Owns:
- `DictationCoordinator`
- hotkey-to-recording flow
- session state machine
- dictation failure handling
- history handoff

### Text Insertion
Owns:
- `TextInsertionService`
- app-profile routing
- AX insertion
- clipboard-preserving paste fallback
- typing fallback
- async timing/success handling

### Persistence and Migration
Owns:
- GRDB schema
- repositories
- migration tracking
- JSON import
- parity verification support

### Voice Memos
Owns:
- memo recording flow
- serialized memo transcription queue
- audio file lifecycle
- transcript/timing persistence handoff
- export flow

### UI Simplification
Owns:
- navigation reduction
- removal of deferred surfaces from v2 navigation
- model profile UI
- dictation/memos/history shell
- vocabulary and learned-corrections UI preservation

## Dependency Order
1. Contract freeze and harnesses
2. Engine, insertion, persistence, and UI shell in parallel
3. Dictation coordinator and memo flow against frozen contracts
4. Integration in this order:
   - engine
   - dictation coordinator
   - insertion
   - history persistence
   - memo queue and memo persistence
   - UI simplification
   - migration verification
   - performance pass

## Quality Gates
- Every slice follows `Red-Green-Refactor`
- Every slice must pass `swift test`
- Any slice touching engine, insertion, or persistence gets a macOS smoke run
- No shared-contract edits without integrator signoff
- No runtime blocking sleeps
- No deletion of legacy JSON until migration parity is verified
- Any performance regression against baseline must be called out before merge

## Target Validation
Unit tests:
- model-profile mapping and typed settings persistence
- deterministic prompt construction
- dictation session transitions with fakes
- insertion routing and fallback order
- SQLite migrations and JSON import correctness

Integration tests:
- end-to-end fake-engine dictation flow
- memo record/transcribe/export flow
- launch with microphone denied while settings/history still work
- prewarm and relaunch behavior

Manual and performance checks:
- recording state visible within 100 ms of hotkey down on Apple Silicon
- first partial text within 1.5 s of speech start for `Balanced`
- median stop-to-insert under 800 ms for common 3-10 second utterances with a prewarmed model
- at least real-time memo transcription throughput for `Balanced`
- no visible main-thread stalls during active dictation in Instruments

## Initial Sub-Agent Prompt Template
Use this pattern for each implementation agent:

1. State the owned files/modules.
2. State the interfaces the agent may depend on.
3. State what the agent must not edit.
4. Require additive, mergeable slices with tests.
5. Require a return summary with:
   - files changed
   - tests added
   - assumptions
   - risks

## First Recommended Day-1 Sequence
1. Freeze contracts and create fakes.
2. Stand up typed settings and model profiles.
3. Build shared engine shell.
4. Build insertion service shell.
5. Build repository protocols and initial GRDB schema shell.
6. Trim the UI shell to the v2 navigation shape behind adapters if needed.
7. Start dictation coordinator against the fake engine before full engine integration.

## Working Assumptions
- `RGR` means `Red-Green-Refactor`
- v2 is macOS-only
- iOS remains out of scope except optional compile-smoke regression checks
- WhisperKit remains the primary engine unless performance targets still miss after the shared-engine refactor
- privacy remains offline-first and local-only by default

## Notes for Future Updates
When implementation begins, update this file with:
- accepted shared contracts
- actual repository file locations for each new module
- migration schema decisions
- benchmark baselines
- any decision that changes sub-agent boundaries
