# Whisper Architecture and Code-Quality Audit

Date: 2026-07-21
Repository: `/Users/quincyobeng/Documents/Code/AI/Claude/Voice-v2`
Commit: `c209d56bfef3388256ffeae67dae44eb7288f7a5`
Branch: `codex/correction-vocabulary-cleanup`
Audit mode: read-only source review plus fresh-path builds/tests. No product code edits, cleanup, commits, pushes, or removals.

## Executive summary

Builds and unit tests pass, but codebase carries high-risk correctness seams hidden by current Swift 5 settings:

1. `TextInjector` can destroy rich/image clipboard content and can replace whole text fields through broad AX fallback.
2. `LiveWhisperEngine` actor permits overlapping model load/inference across `await` suspension points; progress callback order is not preserved.
3. Persistence uses snapshot read-modify-replace operations, allowing lost updates across store instances; corrupt rows and import failures are hidden.
4. iOS custom keyboard attempts microphone dictation, which Apple custom-keyboard sandbox does not support. App-group setup is also missing while code silently falls back to isolated containers.
5. Crash signal handling uses non-async-signal-safe Foundation work and writes to an unsuitable installed-app path.
6. macOS app architecture concentrates windows, preferences, dictation lifecycle, injection, and presentation inside a roughly 1,400-line `AppDelegate`.
7. Default builds emit six unique project warning sites. Opt-in strict-concurrency build emits 49 unique project warning sites, 47 concurrency-specific and two existing `DesignSystem` warnings; many become Swift 6 errors.

Recommended first ship target: correctness characterization and low-risk warning cleanup. Do not start broad architecture extraction until clipboard, persistence, and engine concurrency contracts have tests.

## Repository and verification state

- `NEXT.md`: absent.
- Initial Git state: clean, branch matched upstream (`+0/-0`).
- Tracked files: 125.
- Swift/source-test scale: about 15,619 lines across inspected Swift files and tests.
- Project shapes: SwiftPM package plus `Whisper.xcodeproj`.
- Xcode targets: `WhisperMac`, `WhisperiOS`, `WhisperKeyboard`.
- SwiftPM tests cover `WhisperShared`; Xcode project has no app/UI test target or test plan.

Fresh paths avoided touching or cleaning repo build state:

| Check | Command summary | Result |
|---|---|---|
| macOS app build | `xcodebuild ... -scheme WhisperMac -destination platform=macOS -derivedDataPath /private/tmp/whisper-audit-xcode-019f86ab CODE_SIGNING_ALLOWED=NO build` | Passed |
| iOS app build | `xcodebuild ... -scheme WhisperiOS -destination generic/platform=iOS -derivedDataPath /private/tmp/whisper-audit-ios-019f86ab CODE_SIGNING_ALLOWED=NO build` | Passed |
| keyboard build | `xcodebuild ... -scheme WhisperKeyboard -destination generic/platform=iOS -derivedDataPath /private/tmp/whisper-audit-keyboard-019f86ab CODE_SIGNING_ALLOWED=NO build` | Passed |
| SwiftPM tests | `swift test --scratch-path /private/tmp/whisper-audit-swiftpm-019f86ab` | 235 passed, 0 failed |
| strict-concurrency probe | `swift build --target WhisperShared ... -Xswiftc -warn-concurrency` | Passed under Swift 5; 49 unique project diagnostics |

One scheme-discovery attempt failed before compilation because host sandbox blocked SwiftPM `sandbox-exec`; rerun outside sandbox succeeded. Not project failure.

## Warning inventory

### Default build warnings: six unique project sites

| Location | Warning | Exact remediation | Risk |
|---|---|---|---|
| `Sources/Shared/DesignSystem.swift:49` | Redundant `public` inside `public extension` | Remove method-level `public` | Safe now |
| `Sources/Shared/DesignSystem.swift:53` | Redundant `public` inside `public extension` | Remove method-level `public` | Safe now |
| `Sources/MacApp/WhisperApp.swift:1147` | `activateIgnoringOtherApps` deprecated on macOS 14 | Use cooperative activation API/`activate()` contract; verify target-app focus and fallback behavior | Needs behavior test |
| `Sources/MacApp/VoiceMemosView.swift:50` | Deprecated one-parameter `onChange(of:perform:)` | Use zero- or two-parameter macOS 14 overload | Safe now |
| `Sources/MacApp/VoiceMemosView.swift:601` | Deprecated one-parameter `onChange(of:perform:)` | Use two-parameter overload; consume new value | Safe now |
| `iOS/App/Info.plist:27` | `UIRequiresFullScreen` deprecated at iOS 26 deployment target | Remove key after confirming iPad windowing/product intent; or lower deployment target to real supported floor first | Product choice |

Six unique sites means five Swift source sites plus one plist key. Compiler repeats shared-source warnings across targets/compile jobs. Xcode also printed destination-selection warning because both arm64 and x86_64 matched `platform=macOS`; pin `arch=arm64` in CI to remove tool noise.

### Strict-concurrency probe: 49 unique diagnostics

Current project stays at Swift language 5.0 and does not enable strict-concurrency checking. Probe shows future migration debt:

- Mutable/non-Sendable global state: `SharedStorage.swift:4`, `SQLiteV2Store.swift:31`, `CorrectionEngine.swift:6`, `DictationHistory.swift:30`, `Vocabulary.swift:21`, `VoiceMemoStore.swift:5`.
- AVAudio conversion closure captures: `AudioCapture.swift:127,131,133`, `AudioFileLoader.swift:55,59,61` plus AVFAudio preconcurrency import notes.
- Legacy callback Sendability: `CallbackSetup.swift:14,21,28,34` and corresponding sending diagnostics.
- WhisperKit object transfers: `LiveWhisperEngine.swift:158,385,437` across tokenizer/audio/feature/segment/text decoder and shared `WhisperKit` references.
- Task transfer: `AppAudioStreamTranscriber.swift:190`.
- Main-actor and non-Sendable manager crossings: `VoiceMemoManager.swift:237-243,272,284,297,341,354`.

Do not flip whole project to Swift 6 in one task. Enable targeted warnings, fix one ownership cluster per change, then raise language mode.

## Ranked findings

### Critical/high: safe groundwork now

#### A1. Clipboard preservation loses non-string user data

Evidence: `Sources/MacApp/TextInjector.swift:101-119` snapshots only `.string`, clears all pasteboard types, then restores only string. Error paths during simulated paste can skip restoration. Image, rich text, file, and multi-item clipboard content can be destroyed.

Remediation:

- Introduce pasteboard abstraction for tests.
- Snapshot every `NSPasteboardItem` type/data pair.
- Restore through `defer` on every exit.
- Compare `changeCount` before restore; do not overwrite clipboard if user/app changed it meanwhile.

Files: `TextInjector.swift`, `Tests/TextInjectorTests.swift`. No product behavior change intended.

#### A2. WhisperKit operations can overlap despite actor isolation

Evidence: `Sources/Shared/LiveWhisperEngine.swift:73-103,105-199,421-460`. Actor methods suspend while loading/transcribing. Concurrent prepare, live start, or memo transcription can interleave; older load can publish after newer request. Same WhisperKit encoder/decoder/audio processor can serve memo and live paths together.

Remediation groundwork:

- Inject loader/inference seams and add suspended-operation tests.
- Add keyed single-flight preparation using full `WhisperEnginePreparation` value and generation checks before publishing.
- Serialize all inference against shared WhisperKit instance.

Product choice: queue memo transcription, reject it while live dictation runs, or allocate separate model instance with memory cost.

#### A3. Progress callbacks can arrive out of order

Evidence: `Sources/Shared/AppAudioStreamTranscriber.swift:83-85,127-135,190-197` creates unstructured `Task` per decoder callback. Task scheduling can reorder emitted snapshots; revision records actor arrival, not decoder emission.

Remediation: single ordered `AsyncStream`/serial bridge, source-assigned monotonically increasing sequence, stale-sequence rejection, cancellation/drain during stop. Add deterministic out-of-order callback test.

#### A4. Persistence permits lost updates

Evidence: `Sources/Shared/SQLiteRepositoryStore.swift:20-97` and legacy facades in `DictationHistory.swift:34-40,97-103`, `VoiceMemoStore.swift:9-16,64-70`, `Vocabulary.swift:24-25,158-173` read snapshots, mutate memory, then replace whole tables. Actor isolation covers one repository instance, not multiple stores/processes.

Remediation: add GRDB row-level UPSERT/DELETE/ordered transaction methods; test concurrent writes through two repository instances. Migrate one facade per task.

#### A5. Persistence corruption and import state are hidden

Evidence:

- `SQLiteV2Store.swift:424-467`: malformed UUID becomes new UUID on every read; malformed transcript words become `nil`.
- `SQLiteV2Store.swift:287-362,482-485`: absent legacy file decodes like empty input and gets permanently marked imported.
- `SQLiteV2Store.swift:50-68`: storage initialization calls `fatalError` for filesystem, migration, or import failures.

Remediation:

- Throw typed row-decoding corruption errors; never synthesize identity.
- Distinguish missing, malformed, imported, skipped-nonempty outcomes.
- Mark source imported only when source existed and outcome was recorded.
- Replace runtime `fatalError` with throwing factory plus user-visible persistence health.

#### A6. Audio loader can return truncated success

Evidence: `Sources/Shared/AudioFileLoader.swift:27-66`. Fractional output capacity truncates toward zero; tiny final chunks can get zero capacity. Buffer allocation failure breaks loop and returns partial samples. Conversion error collapses into misleading creation error.

Remediation: `max(1, ceil(...))` plus converter allowance; throw allocation/conversion error with underlying cause; never return partial success. Test one-frame tail, 44.1/48 kHz stereo, and failure seams.

#### A7. Crash reporting path and signal handler unsafe

Evidence: `Sources/MacApp/CrashReporter.swift:21-25,52-70`. Report path sits beside app bundle, often becoming unwritable `/Applications/Logs`. Signal handler allocates Foundation objects, formats strings/dates, and uses APIs not async-signal-safe.

Remediation: normal reports under `~/Library/Logs/Whisper` or Application Support with surfaced setup failure. For signals, either rely on OS crash reports or precompute descriptor/bytes and restrict handler to `open/write/close/_exit`. Risky platform change; isolate and crash-harness test.

### High: product/platform decisions required

#### B1. iOS keyboard dictation design conflicts with platform contract

Evidence: `iOS/Keyboard/KeyboardViewController.swift:107-168` records microphone and performs local model work inside custom keyboard. Apple states custom keyboards have no microphone access. `iOS/Keyboard/Info.plist:31-32` sets `RequestsOpenAccess=false`, preventing shared-container writes; both app/keyboard entitlement files contain no app group. `SharedStorage.baseDirectory()` silently falls back to process-local Application Support.

Decision:

- Redesign dictation through containing app/system surface; custom keyboard only receives finished shared text.
- Provision same app-group entitlement on app and extension.
- Decide whether keyboard needs Full Access. Full Access changes privacy promise but still does not grant microphone.
- Fail visibly when configured group container cannot resolve.

Apple sources:

- [Configuring open access for a custom keyboard](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)
- [Custom Keyboard programming guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)

#### B2. AX fallback can overwrite wrong field or whole field

Evidence: `TextInjector.swift:148-168,219-232,242-275`. When focused insertion fails, code breadth-first searches window for first editable element, then sets entire `kAXValue`.

Decision/remediation: restrict to focused element unless app-specific profile opts in. Implement range-aware replacement from `kAXSelectedTextRange`; if unavailable, return false and use paste fallback. Add fake AX adapter tests before changing compatibility behavior.

#### B3. Final-tail decode failure invalidates otherwise successful dictation

Evidence: `LiveWhisperEngine.swift:286-299,402-419`. Any residual final-flush error throws terminal failure even when live snapshot exists.

Decision: strict completeness or best-effort. Recommended user contract: report diagnostic and complete with last valid transcript unless no usable transcript exists.

#### B4. macOS distribution/security policy undefined

Evidence: no Mac entitlements, hardened-runtime setting, or sandbox setting. App needs mic and Apple Events. No app-owned `PrivacyInfo.xcprivacy`; dependencies may carry their own manifests but app API use still needs audit.

Decision: direct distribution vs Mac App Store. Then add hardened runtime, sandbox/Apple Events entitlements if applicable, and privacy manifest based on actual API scan. Apple source: [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files).

#### B5. Persistence V2 seam is orphaned

Evidence: `SQLiteRepositoryStore` and five repository protocols have no production references; tests instantiate them. Production uses snapshot singletons. `UserDefaultsSettingsStore` also has test-only references while app uses `LegacyAppPreferencesSettingsStore`.

Decision: migrate production facades onto repository/store design or remove abandoned V2 layer after compatibility review. Do not maintain both indefinitely.

### Medium: architecture, UX, testability, organization

#### C1. AppDelegate monolith and duplicate settings lifecycles

Evidence: `WhisperApp.swift:18-1409` owns preferences, window factories, engine/coordinator, hotkeys, dictation, injection, and presentation. Native SwiftUI `Settings` scene at `:7-15` coexists with manual Settings `NSWindow` at `:595-621`.

Remediation sequence after characterization tests:

1. Choose native Settings scene or manual window.
2. Extract window ownership to `AppWindowController` without moving dictation behavior.
3. Extract dictation presentation/orchestration to `DictationSessionController` without changing engine.
4. Keep SwiftUI value state as source of truth; use narrow AppKit bridge for windows/focus.

#### C2. Prompt provider reads mutable singleton stores from Sendable closure

Evidence: `DefaultTranscriptionPromptProvider.swift:3-39` reads `Vocabulary` and `CorrectionEngine`, both mutable non-actor classes. `@Sendable` closure does not make access safe.

Remediation: isolate repositories on actor/lock/MainActor, make provider snapshots async, then await immutable values. Add concurrent mutation/prompt test and Thread Sanitizer run.

#### C3. VoiceMemoManager actor ownership unclear

Strict probe reports main-actor violations and non-Sendable captures at `VoiceMemoManager.swift:237-243,272,284,297,341,354`. File also ignores delete/export errors at `:164-173,234-245`, allowing DB/file divergence and silent export failure.

Remediation: mark UI-facing manager `@MainActor`, move transcription queue into actor/service, return typed delete/export results, update metadata only after successful or explicitly missing-file handling.

#### C4. Permission UI becomes stale

Evidence: `SettingsView.swift:624-665` queries permission during body evaluation; async microphone completion and external accessibility changes do not invalidate view.

Remediation: state-backed permission snapshot refreshed on appear, app activation, and request completion.

#### C5. Accessibility and keyboard support gaps

Evidence:

- Hover-only history row actions: `HistoryView.swift:296-340,410-434`.
- Memo selection only by tap gesture: `VoiceMemosView.swift:334-337`.
- Shape-only record controls: `MainView.swift:124-143`, `VoiceMemosView.swift:153-169`.
- Hotkey recorder lacks useful accessibility role/value/action: `HotkeyRecorderView.swift:57-170`.

Remediation: retain actions in accessibility/focus tree, use `List(selection:)`, add explicit labels/hints, keyboard activation, accessibility value/press action. Verify with VoiceOver and keyboard-only pass.

#### C6. UI behavior drift and misleading state

- History sizing conflicts: `HistoryView.swift:35` requests 680x500 while `WhisperApp.swift:627-639` fixes 600x450.
- Start action stays enabled outside ready/recording states: `MainView.swift:82-111`; delegate silently guards at `WhisperApp.swift:695-706`.
- Immersive view always says Caps Lock stops recording: `ImmersiveWaveformView.swift:94-107`, even custom-hotkey or processing states.
- Injection error path copies debug annotation but reports only final text: `WhisperApp.swift:966-984`.
- History paste failure silently copies: `HistoryView.swift:248-256`.

Remediation: align window ownership/sizing, state-gate actions, inject current stop affordance/status, keep clipboard payload clean, surface structured insertion/paste result.

#### C7. Preferences and project configuration drift

- Silence default: 1.44 in `WhisperApp.swift:145`, 1.5 in `SettingsView.swift:24`.
- Recording modes repeated as strings across `MainView.swift`, `WhisperApp.swift`, and private Settings enum.
- Wave color keys persisted by Settings but no renderer reads found.
- Package floor macOS 14/iOS 17; Xcode project sets iOS 26 and Swift 5.0.
- Plists hardcode version `1.0/1` while project defines marketing/build versions.
- Mac plist names `WhisperV2` icon, but target has no resource phase/file reference for `Design/Generated/WhisperV2.icns` and also sets missing `AppIcon` asset name.

Remediation: central typed keys/defaults; decide custom-wave-color feature; choose supported iOS floor; align Swift/package/project settings; use build variables in plists; add one valid Mac icon mechanism and inspect built bundle.

#### C8. Test architecture misses integration contracts

Strong unit coverage exists for coordinator races and pure helpers. Missing:

- Live engine start/permission/partial/cancel/stop/final/failure integration.
- Ordered AppAudioStreamTranscriber callbacks.
- Multi-instance persistence writes and corrupt/missing/malformed import cases.
- App startup, plist, entitlements, resources, and keyboard-container contract.
- macOS injection against pasteboard/AX abstractions.
- UI/VoiceOver/keyboard smoke tests.

Add seams and tests before broad refactor.

## Dead/stale code candidates — evidence only, no deletion approved

| Candidate | Evidence | Decision before removal |
|---|---|---|
| `AudioCapture.swift`, `Transcriber.swift`, `CallbackSetup.swift` | No production roots; only internal cluster references. Git history indicates roots removed in `999fda2`. | Confirm `WhisperShared` has no external API consumers; delete cluster together if internal-only. |
| Mac `ASCIICanvasView.swift` + `ASCIIOverlayView.swift` | Files reference each other; no Mac construction/use found. iOS owns separate copies. | Confirm target/link symbol inventory and product intent. |
| Processing bar path | `setupProcessingBarWindow` only called by `showProcessingBar`; `showProcessingBar` has no call sites. Window only hidden elsewhere. | Confirm no Objective-C/dynamic selector use; remove as isolated task. |
| `LiveWhisperEngine.moreCompleteSnapshot` | Private definition at `LiveWhisperEngine.swift:698-715`, zero call sites. | Safe removal after focused tests/build. |
| Sync legacy TextInjector methods | `type`, `paste`, `insertIntoFocusedElement` have zero call sites; adapter uses async/advanced methods. | Confirm no external API compatibility need. |
| `SettingsView.stopHotkeyDisplay` | Definition only, zero references. | Safe removal after build. |
| `WhisperApp.setupSettingsWindow()` no-arg overload | Definition only, zero references. | Safe removal after build. |
| `AppAudioStreamTranscriber.currentFallbacks/unconfirmedText` | Written/reset internally; sole snapshot consumer does not read them. | Remove or intentionally wire into transcript semantics after tests. |
| `MigrationStateSnapshot.parityVerifiedSources` | Persisted/read but no production producer; test-only supplied value. | Finish parity feature or remove field through migration-safe plan. |
| `BoundedFinalAudioWindow.decodedSampleCount` | Test-read only; production uses range. | Safe cleanup with test adjustment. |

Dead-code rule: zero static references supports candidacy, not proof of safe deletion for public library APIs, selectors, reflection, serialized fields, or product-disabled features.

## Prioritized remediation plan

### Safe now

1. Warning-only cleanup: `DesignSystem.swift`, `VoiceMemosView.swift`; build all three schemes and run 235 tests.
2. Clipboard characterization and preservation: `TextInjector.swift`, `TextInjectorTests.swift`.
3. Persistence corruption/import semantics: `SQLiteV2Store.swift`, `SQLiteRepositoryStoreTests.swift`.
4. Atomic row operations and two-instance race tests: `SQLiteV2Store.swift`, `SQLiteRepositoryStore.swift`, focused tests.
5. Live engine injection seams and lifecycle tests; no policy change.
6. Ordered progress bridge: `AppAudioStreamTranscriber.swift` plus new tests.
7. Audio file loader errors/capacity: `AudioFileLoader.swift` plus new tests.
8. Permission refresh and accessibility labels/selection, one view per change.
9. Plist version variables and Mac icon resource wiring; verify built bundles.
10. Remove proven private/local dead declarations only, one candidate family per change, after tests/build.

### Needs product choice

1. iOS keyboard dictation replacement flow and Full Access policy.
2. Memo inference policy during live dictation: queue, reject, or second model.
3. Best-effort vs strict final-tail transcription failure.
4. AX target-search compatibility vs focused-element safety.
5. Direct distribution vs Mac App Store sandbox/entitlements.
6. Real iOS deployment floor and iPad windowing behavior.
7. Migrate to repository V2 seam vs delete abandoned seam.
8. Custom waveform color: wire feature or remove ineffective control.

### Risky; defer behind characterization tests

1. Crash signal-handler replacement.
2. AppDelegate split/window lifecycle rewrite.
3. Singleton persistence-to-actor migration.
4. Swift 6 language-mode switch.
5. Custom keyboard product redesign.
6. Bulk dead-code deletion or public `WhisperShared` API break.

## Incremental implementation sequence

Each task should remain independently buildable and reviewable.

1. **Default warning cleanup** — `DesignSystem.swift`, `VoiceMemosView.swift`; leave activation/plist decisions out.
2. **Pasteboard safety tests** — add pasteboard protocol/fake in `TextInjector.swift` and tests; characterize string, RTF, image, file, multi-item, failure, concurrent-change cases.
3. **Pasteboard safety fix** — same files only; preserve all items and guard restoration.
4. **Persistence decode contract** — `SQLiteV2Store.swift` plus malformed-row tests.
5. **Legacy import state contract** — same store plus missing/malformed/idempotent/nonempty/partial-source tests.
6. **Atomic persistence methods** — store/repository plus two-instance tests; no facade migration yet.
7. **Live engine seams** — protocols/factories and deterministic lifecycle tests; preserve behavior.
8. **Progress ordering** — `AppAudioStreamTranscriber.swift` and focused tests.
9. **Inference policy decision implementation** — `LiveWhisperEngine.swift` only after decision; keyed load gate and operation serialization.
10. **Audio loader hardening** — `AudioFileLoader.swift` and focused tests.
11. **Voice memo ownership** — `VoiceMemoManager.swift`; `@MainActor` UI owner plus separate actor queue; typed file-operation errors.
12. **Prompt-store isolation** — `Vocabulary.swift`, `CorrectionEngine.swift`, provider, focused tests.
13. **UI accessibility/state** — one file per change: `MainView`, `HistoryView`, `VoiceMemosView`, `HotkeyRecorderView`, `SettingsView`.
14. **Project resource/config cleanup** — project file, icon asset/resource, three plists; built-bundle inspection.
15. **Dead-code proposal** — verify symbols/public API, then separate removal review. No combined architecture refactor.
16. **Window extraction** — characterization screenshots first; extract `AppWindowController`.
17. **Dictation extraction** — move orchestration after window change stabilizes.
18. **Swift 6 migration** — targeted strict diagnostics by cluster, then language-mode change last.

## Stop condition reached

Manager audit complete. Builds/tests executed. Warnings inventoried. Dead code identified with evidence only. No product behavior or source code changed. Broad refactor, feature removal, merge, commit, and push intentionally not started.

Final Git status: two untracked audit artifacts, `Design/ARCHITECTURE_CODE_QUALITY_AUDIT_2026-07-21.md` and `Design/AuditScreenshots/capture-environment.jpeg`. Screenshot appeared during delegated audit tooling despite agent reporting no writes; preserved rather than deleted. No tracked-file modifications.

## Exact next prompt

> Work in `/Users/quincyobeng/Documents/Code/AI/Claude/Voice-v2`. Read `Design/ARCHITECTURE_CODE_QUALITY_AUDIT_2026-07-21.md`, read `NEXT.md` if present, and inspect Git status. Preserve all unrelated work; no reset, clean, checkout, force, commit, push, release, or feature removal. Implement only remediation task 1: remove default compiler warnings in `Sources/Shared/DesignSystem.swift` and `Sources/MacApp/VoiceMemosView.swift`. Do not change `WhisperApp.swift:1147` activation behavior or `iOS/App/Info.plist:27` until product decisions are made. Run fresh-path SwiftPM tests and fresh-path macOS/iOS/keyboard builds; inventory remaining warnings. Stop after verification and report diff plus Git status.
