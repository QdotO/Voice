# Whisper Master Implementation Plan

Sources:

- `Design/ARCHITECTURE_CODE_QUALITY_AUDIT_2026-07-21.md`
- `Design/WHISPER_UI_UX_AUDIT_2026-07-21.md`
- `Design/WHISPER_UI_UX_IMPLEMENTATION_PLAN_2026-07-21.md`

Audience: GPT-5.6 Luna implementers.
Manager rule: one active ship target, serial review, no overlapping file ownership.

## Operating contract

Every task must:

1. Read all three source artifacts, `NEXT.md` if present, current Git status, and current diff for owned files.
2. Preserve unrelated dirty work. Stop on ownership collision.
3. Edit only owned files. No reset, clean, checkout, stash, commit, push, release, permission change, or user-data mutation.
4. Add characterization tests before behavior changes when task touches persistence, clipboard, AX, audio lifecycle, or concurrency.
5. Run focused tests, full `swift test`, `git diff --check`, and `bash ./scripts/build_xcode_mac.sh` unless scope names different platform builds.
6. Report exact diff, proof, remaining warnings, manual checks, and Git status.

## Progress ledger

| ID | Finding/task | Status | Owner files |
|---|---|---|---|
| ARC-01 | Default warning cleanup | Complete; uncommitted | `DesignSystem.swift`, `VoiceMemosView.swift` |
| ARC-02 | Pasteboard characterization seam/tests | Complete; uncommitted | `PasteboardTextTransaction.swift`, `TextInjector.swift`, tests |
| ARC-03 | Preserve full pasteboard safely | Complete; 243 tests + Mac build | same pasteboard files |
| ARC-04 | Persistence decode corruption contract | Complete; 248 tests + Mac build | `SQLiteV2Store.swift`, tests |
| ARC-05 | Legacy import outcome contract | Complete; 254 tests + Mac build | `SQLiteV2Store.swift`, tests |
| ARC-06 | Atomic row persistence operations | Complete; 257 tests + Mac build | SQLite store/repository/focused tests |
| ARC-07 | Migrate production facades to atomic repository | Complete; History, Vocabulary, Corrections, Voice Memos atomic (333 tests + Mac build); Settings closed N/A—production legacy store is read-only and AppStorage writes per key | one facade per task |
| ARC-08 | Live engine loader/inference seams | Complete; 264 tests + Mac build | `LiveWhisperEngine.swift`, new tests/support |
| ARC-09 | Ordered progress bridge | Complete; 268 tests + Mac build | `AppAudioStreamTranscriber.swift`, tests |
| ARC-10 | Single-flight preparation + inference queue | Complete; 269 tests + Mac build | `LiveWhisperEngine.swift`, tests |
| ARC-11 | Final-tail best-effort policy | Complete; 274 tests + Mac build | engine/tests |
| ARC-12 | Audio loader hardening | Complete; 284 tests + Mac build | `AudioFileLoader.swift`, tests |
| ARC-13 | Voice memo actor/file ownership | Complete; 303 tests + Mac build; owned strict-concurrency clean | `VoiceMemoManager.swift`, `WhisperApp.swift`, tests |
| ARC-14 | Prompt-store isolation | Complete; 308 tests + TSAN + Mac build; owned strict-concurrency clean | Vocabulary/Correction/provider/tests |
| ARC-15 | AX focused-element safety | Complete; 313 tests + Mac build | `TextInjector.swift`, AX seam/tests |
| ARC-16 | Permission state refresh | Complete; 320 tests + Mac build | Settings permission model/view |
| ARC-17 | Crash reporting safety | Complete; subprocess harness + signal-safe writer + user Logs path verified | `CrashReporter.swift`, tests/harness |
| ARC-18 | iOS keyboard shared-container/product flow | Decision gate | iOS app/keyboard/entitlements |
| ARC-19 | Project config/resources/version/icon | Partial; versions + iOS 17/full-screen + Mac icon complete (333 tests + all 3 builds); distribution policy blocked on direct vs Mac App Store decision | project/plists/resources |
| ARC-20 | AppDelegate window extraction | Blocked on explicit Settings lifecycle choice: native scene vs manual tabbed window | App/window files |
| ARC-21 | Dictation session extraction | Blocked until ARC-20 lifecycle choice | orchestration files |
| ARC-22 | Strict-concurrency clusters/Swift 6 | Complete; SwiftPM + Xcode Swift 6, 338 tests, crash harness, Mac/iOS/keyboard builds | one cluster per task |
| DEAD-01 | Proven visual-path dead declarations | Complete; 294 tests + Mac build | removed Mac ASCII/processing path |
| DEAD-02 | Private unused declarations | Complete; 333 tests + all 3 builds | engine/settings/app files |
| DEAD-03 | Legacy synchronous TextInjector methods | Complete; 333 tests + all 3 builds | `TextInjector.swift`, tests |
| DEAD-04 | AudioCapture/Transcriber/CallbackSetup public API cluster | Retained; live iOS app + keyboard call sites proven | shared audio files |
| DEAD-05 | Persisted migration parity field | Blocked; removal breaks public `MigrationStateSnapshot` API and needs schema/API compatibility decision | contracts/store/tests |
| UI-01…UI-17 | Complete UI audit ledger | Complete; detailed UI slices 1–7 verified, screenshot/VoiceOver capture blocked by display permission | detailed UI plan |

## Architecture task cards

### ARC-03 — full pasteboard preservation

Owned files: current ARC-02 files only.
Goal: snapshot all pasteboard items/types/data; restore through `defer`; never overwrite concurrent user/app clipboard change.
Required cases: string, RTF, image, file URL, multiple items, simulated paste failure, concurrent change.
Invariant: insertion timing/key events unchanged.
Acceptance: ARC-02 characterization tests updated from known-bug assertions to preservation assertions; focused/full tests and Mac build pass.

### ARC-04 — row-decoding corruption

Owned: `Sources/Shared/SQLiteV2Store.swift`, focused SQLite tests.
Goal: malformed UUID/transcript words throw typed corruption error; never synthesize UUID or silently nil malformed fields.
Add tests before code for malformed identity, malformed word JSON, valid legacy nil, mixed valid/corrupt rows.
Invariant: schema and valid-row decoding unchanged.
Acceptance: typed error includes table/row/column context without sensitive transcript logging.

### ARC-05 — legacy import outcome

Owned: same store plus import tests.
Define outcomes: missing, malformed, imported(count), skippedNonempty, partialFailure.
Mark source complete only when source existed and durable outcome recorded. Missing file remains retryable/not imported.
Tests: missing, malformed, empty valid, nonempty destination, idempotent rerun, partial multi-source failure.

### ARC-06 — atomic repository operations

Owned: `SQLiteV2Store.swift`, `SQLiteRepositoryStore.swift`, repository tests.
Add row UPSERT/DELETE and ordered transactional methods. Keep snapshot replace APIs temporarily.
Test two independent repository instances writing interleaved records; no lost updates.
No production facade migration.

### ARC-07 — production facade migration

One task per facade: History → Vocabulary → Corrections → Voice Memos → Settings.
Each task owns facade, repository interface, tests.
Replace snapshot read-mutate-replace with atomic operations. Preserve notifications, ordering, AppStorage keys, legacy import.
Do not migrate two facades together.

### ARC-08 — engine test seams

Owned: `LiveWhisperEngine.swift`, narrow protocols/fakes, focused tests.
Inject model loader and inference operation without changing policy.
Characterize concurrent prepare, start during prepare, memo during live, cancellation, stale completion, final flush.
No serialization fix yet.

### ARC-09 — ordered progress

Owned: `AppAudioStreamTranscriber.swift`, focused tests.
Replace unstructured Task-per-callback with one serial bridge. Assign source sequence before enqueue; reject stale sequence; drain/cancel deterministically on stop.
Test deliberately reversed callback scheduling.

### ARC-10 — single-flight and inference queue

Owned: `LiveWhisperEngine.swift`, ARC-08 tests.
Decision: one shared model instance; keyed preparation by full `WhisperEnginePreparation`; latest generation may publish; all inference serialized; memo transcription queues behind live dictation.
Acceptance: no overlapping fake inference; stale prepare never publishes; cancellation cannot deadlock; queued memo begins after live completion.

### ARC-11 — final-tail policy

Owned: engine finalization/tests.
Decision: if final residual decode fails and usable live transcript exists, complete with last valid transcript plus diagnostic. Throw only when no usable transcript exists.
Test successful tail, failed tail with snapshot, failed tail without snapshot, no duplicate text.

### ARC-12 — audio loader

Owned: `AudioFileLoader.swift`, tests.
Use `max(1, ceil(...))` output capacity plus converter allowance. Throw typed allocation/conversion errors with underlying cause. Never return partial success.
Test one-frame tail, 44.1/48 kHz stereo, converter failure, allocation failure.

### ARC-13 — VoiceMemoManager ownership

Owned: manager, extracted queue actor/service, focused tests.
Mark UI manager `@MainActor`; move transcription queue off-main into actor; return typed delete/export results; update DB metadata only after successful/missing-file policy.
Preserve public UI behavior and current dirty `VoiceMemosView` lines.

### ARC-14 — prompt stores

Owned: `Vocabulary.swift`, `CorrectionEngine.swift`, `DefaultTranscriptionPromptProvider.swift`, tests.
Provide actor/locked async immutable snapshots; build prompt from awaited snapshots.
Test concurrent mutation while prompt builds; run Thread Sanitizer when feasible.

### ARC-15 — AX safety

Owned: `TextInjector.swift`, AX abstraction, tests.
Decision: focused element only unless explicit app profile opts in. Use `kAXSelectedTextRange` for replacement. If unavailable, return false and use preserved-paste fallback. Remove breadth-first first-editable-element overwrite path.
Test focused range, missing range, wrong element, profile opt-in, fallback, clipboard cleanliness.

### ARC-16 — permission refresh

Owned: permission state model + `SettingsView` permission section.
Refresh on appear, app activation, and request completion. No automatic permission prompts/settings changes.
Test state reducer; visually verify granted/denied/stale-to-fresh.

### ARC-17 — crash reporting

Owned: `CrashReporter.swift`, isolated harness/tests.
Move normal reports to `~/Library/Logs/Whisper` or Application Support. Replace signal-time Foundation work with OS crash reports or precomputed fd/bytes using only async-signal-safe calls.
Must have subprocess crash harness before behavior change.

Complete: `scripts/test_crash_reporter.sh` compiles production `CrashReporter.swift` with isolated `Tests/CrashReporterHarness/main.swift`, verifies default `~/Library/Logs/Whisper` directory resolution without writing there, then raises `SIGABRT` in a temp subprocess and verifies exit 134 plus emitted signal record. Production setup pre-opens append-only fd and preallocates fixed signal records; handler performs only `write`, handler reset, and `raise`. Foundation formatting remains outside signal path. Harness, strict probe, 338 tests, macOS build, and `git diff --check` pass.

### ARC-18 — iOS keyboard flow

Blocked product decision. Recommended target: containing app owns microphone/model; keyboard consumes finished text through configured App Group. Add same app-group entitlement to app/extension; fail visibly if group missing. Full Access does not grant microphone.
Requires explicit privacy/distribution approval before implementation.

### ARC-19 — project configuration

Owned: one configuration family per task.

1. Versions: use build variables in three plists.
2. Deployment: align Xcode iOS floor to 17 unless product overrides; remove `UIRequiresFullScreen` after iPad behavior check.
3. Mac icon: choose one valid asset/resource path; inspect built bundle.
4. Distribution: direct-distribution default pending explicit confirmation; hardened runtime/privacy manifest/Apple Events entitlements audited separately.

Build all three schemes after each family.

### ARC-20/21 — architecture extraction

Only after UI layout/live-state slices stabilize.

- ARC-20: choose one Settings lifecycle; extract `AppWindowController`; preserve screenshot/window contract.
- ARC-21: extract `DictationSessionController`; keep AppDelegate as lifecycle/wiring adapter.

Each extraction needs characterization screenshots and no behavior change.

### ARC-22 — strict concurrency

One cluster per task: storage globals → audio conversion closures → callback bridge → WhisperKit transfers → VoiceMemoManager. Enable warnings per target; zero new diagnostics; switch Swift language mode only after all clusters pass.

Completed evidence: storage globals, SharedStorage, LiveWhisperEngine/WhisperKit transfer boundary, AudioCapture/AudioFileLoader conversion state, AppAudioStreamTranscriber ordered progress bridge, CallbackSetup `@Sendable`/main-actor callback bridge, main-actor `StatusViewModel` and `Transcriber`, concurrency-safe AX prompt key, actor-owned coordinator settings store, macOS 14 activation API, lock-backed notification counters and AudioCapture callback capture, ARC-17 signal-safe crash globals, and explicit `AudioCapture` Sendable boundary around locked callback/sample state. SwiftPM and both Xcode configurations now use Swift 6. Verification: 338 tests, crash subprocess harness, Mac app build, generic iOS build embedding keyboard, standalone keyboard scheme build, and `git diff --check` pass.

## Dead-code task cards

Serial candidate families:

1. Private unused declarations: `moreCompleteSnapshot`, `stopHotkeyDisplay`, no-arg `setupSettingsWindow`.
2. Processing bar + Mac ASCII visual path, coordinated with UI Slice 6.
3. Legacy synchronous TextInjector methods after AX/pasteboard work.
4. AudioCapture/Transcriber/CallbackSetup cluster only after public API/symbol check.
5. Persisted migration fields only through migration-safe schema plan.

Zero `rg` references is necessary, not sufficient. Build all platforms after removal.

## UI track

Execute detailed tasks exactly from `WHISPER_UI_UX_IMPLEMENTATION_PLAN_2026-07-21.md`:

1. Semantic design foundation. **Complete: 284 tests + Mac build; visual capture blocked by display permission.**
2. Live-state truth, copy, custom floating waveform color, recovery, stable island. **Complete: 290 tests + Mac build; visual capture blocked.**
3. Window/layout contracts. **Complete: 290 tests + Mac build; visual capture blocked.**
4. History controls/deletion. **Complete: 294 tests + Mac build; visual/VoiceOver capture blocked.**
5. Voice Memo controls/deletion. **Complete: 294 tests + Mac build; visual/VoiceOver capture blocked.**
6. Motion/VoiceOver/keyboard. **Complete: 294 tests + Mac build; visual capture blocked.**
7. Dead visual path decision/removal. **Complete: 294 tests + Mac build.**

UI tasks start after ARC-03 because both affect `TextInjector` only indirectly but manager wants correctness baseline first. ARC-16 merges into UI accessibility slice. Dead visual cleanup runs once.

## Dispatch order

1. ARC-03.
2. ARC-04 → ARC-06.
3. ARC-08 → ARC-12.
4. UI foundation → UI live-state → UI layout/controls/accessibility.
5. ARC-13 → ARC-16.
6. ARC-07 facade migrations, one at time.
7. ARC-19 config families.
8. Dead-code families.
9. ARC-20/21 extraction.
10. ARC-22 concurrency clusters.
11. ARC-17 crash safety and ARC-18 keyboard flow after explicit gates.

## Completion definition

- Every ledger row marked complete, deferred with explicit user decision, or killed with evidence.
- Full SwiftPM suite passes.
- macOS/iOS/keyboard builds pass with zero default warnings.
- No known clipboard/persistence lost-update path remains.
- UI capture matrix, keyboard, VoiceOver, Reduce Motion checks recorded.
- Git diff reviewed; unrelated work preserved; no commit/push unless separately requested.
