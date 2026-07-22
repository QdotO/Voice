# Whisper UI/UX Implementation Plan

Audience: GPT-5.6 Luna implementers
Source audit: `Design/WHISPER_UI_UX_AUDIT_2026-07-21.md`
Rule: one slice at a time; no overlapping file ownership; preserve every unrelated change

## 0. Agent contract

Every Luna task must follow this contract:

1. `cd /Users/quincyobeng/Documents/Code/AI/Claude/Voice-v2`.
2. Read `NEXT.md` if present.
3. Run `git status --short --branch` and `git diff -- <owned files>` before editing.
4. Edit only listed owned files. Stop and report conflict if an owned file changes during task.
5. Never reset, clean, checkout, stash, commit, push, release, delete user data, or change permissions.
6. Preserve behavior unless task explicitly changes named behavior.
7. Use `apply_patch` for edits.
8. Run focused tests first, then `swift test`, then `bash ./scripts/build_xcode_mac.sh`. Do not use `build.sh` unless manager approves stopping running app.
9. Do not launch app or alter TCC permissions unless task explicitly requests visual verification.
10. Return: findings addressed, exact files/lines changed, tests/build output, screenshots or explicit visual blocker, remaining risks, `git status --short`.

Current collision warning: `Sources/Shared/DesignSystem.swift` and `Sources/MacApp/VoiceMemosView.swift` already contain unrelated uncommitted warning-cleanup edits. Luna must build on them, never overwrite them.

## 1. Finding ledger

| ID | Finding | Planned slice | Done proof |
|---|---|---|---|
| UI-01 | Immersive stop hint lies | 2 | tests cover Caps Lock enabled/disabled and configured stop shortcut |
| UI-02 | History view/window size mismatch | 3 | source contract + minimum/default screenshots |
| UI-03 | Custom wave-color setting has no consumer | 2 | product decision implemented and tested |
| UI-04 | Fixed windows and two-column Main grid | 3 | resize matrix passes |
| UI-05 | History actions hover-only/small | 4 | keyboard and pointer walkthrough |
| UI-06 | Voice Memo selection/record affordance weak | 4 | keyboard/VoiceOver walkthrough |
| UI-07 | Destructive actions inconsistent | 4 | confirmation/undo policy tests |
| UI-08 | Reduce Motion ignored | 5 | reduced-motion visual/runtime proof |
| UI-09 | Fragmented color language | 1 | raw-color inventory shrinks; screenshots approved |
| UI-10 | Fragmented control language | 1 + 4 | shared component adoption |
| UI-11 | Conflicting state copy | 2 | one state-copy source + tests |
| UI-12 | Conflicting setting nouns | 2 | copy inventory passes |
| UI-13 | Error text truncates; no recovery | 2 | typed errors + recovery routing tests |
| UI-14 | Status item accessibility never reflects state | 2 | state-to-label tests/manual VoiceOver check |
| UI-15 | Immersive state hidden from accessibility | 5 | announcements or equivalent state surface verified |
| UI-16 | Floating island width jumps | 2 | width policy tests/recording→processing capture |
| UI-17 | Dead ASCII/processing visual paths | 6 | product decision + zero unreferenced runtime paths |

## 2. Slice order and ownership

Do not parallelize slices 1–3. Slice 4 can split by History vs Voice Memos only after Slice 1 components stabilize. Slice 5 follows 2–4. Slice 6 last.

| Slice | Owned files | Depends on |
|---|---|---|
| 1. Design foundation | `DesignSystem.swift`, `MainView.swift`, `StatusView.swift`, focused new tests | Architecture audit merge gate |
| 2. Live-state truth | `StatusView.swift`, `ImmersiveWaveformView.swift`, `WhisperApp.swift`, `SettingsView.swift`, new state-policy helpers/tests | Slice 1 |
| 3. Window/layout repair | `WhisperApp.swift`, `MainView.swift`, `HistoryView.swift`, `VoiceMemosView.swift`, `SettingsView.swift` | Slice 1; Slice 2 merged |
| 4A. History controls | `HistoryView.swift`, `WhisperApp.swift`, optional focused helper/tests | Slice 1 + 3 |
| 4B. Voice Memo controls | `VoiceMemosView.swift`, `MainView.swift`, optional focused helper/tests | Slice 1 + 3; no concurrent 4A file overlap |
| 5. Accessibility/motion | all touched UI files, one sequential owner | Slices 2–4 |
| 6. Dead-path cleanup | `ASCIIOverlayView.swift`, `ASCIICanvasView.swift`, `ImmersiveProcessingView.swift`, `WhisperApp.swift` | product decision; all prior slices |

## 3. Slice 1 — semantic design foundation

Addresses UI-09 and foundation half of UI-10.

### Owned files

- `Sources/Shared/DesignSystem.swift`
- `Sources/MacApp/MainView.swift`
- `Sources/MacApp/StatusView.swift`
- New focused tests only when logic can live in `WhisperShared`

### Ordered edits

1. Preserve current access-control warning cleanup in `DesignSystem.swift`.
2. Add nested semantic namespaces or equivalent stable API:
   - surfaces: canvas, surface, raised, inset
   - text: primary, secondary, tertiary
   - strokes: subtle, strong
   - states: active orange/coral, processing amber, success, warning, danger, info
   - spacing: 4/8/12/16/24/32
   - radii: 8/12/16/24
   - control heights: 32/36/44
3. Keep existing `backgroundGradient`, `accentGradient`, `glassCard`, and `mainBackground` as compatibility aliases for this slice. Mark with comments if migration is pending; do not remove API.
4. Add shared styles/components with narrow inputs:
   - `WhisperCard` or card modifier: raised/selected state only
   - primary button style: active, busy, destructive variants
   - icon button style: standard target, hover/focus visuals
   - status chip: icon + label + semantic role
5. Change `MainView` only where direct replacement is mechanical: root background, Bento cards, primary dictation action, record action colors, headers/secondary text.
6. Change `StatusView` only where direct replacement is mechanical: capsule surfaces/strokes and semantic active/processing/error colors. Do not change state strings, widths, animation, or callbacks.
7. Run `rg` inventory for raw `Color.red`, `.blue`, `.green`, `.purple`, `Color.white.opacity`, and arbitrary corner radii. Report remaining instances; do not expand scope.

### Invariants

- Same Main tiles, callbacks, AppStorage keys, status states, and window sizes.
- Orange/coral is primary active identity. Red remains error/destructive.
- No iOS changes.
- No removal of existing public/used styling API.

### Verification

- `swift test`
- `bash ./scripts/build_xcode_mac.sh`
- Compile previews if available.
- Visual: Main ready + recording; floating status ready + recording.
- Compare raw-color inventory before/after.

### Stop conditions

- Stop if architecture audit changes `DesignSystem.swift` beyond current warning-only diff.
- Stop if component extraction requires behavior/state ownership changes.

## 4. Slice 2 — live-state truth and copy

Addresses UI-01, UI-03, UI-11, UI-12, UI-13, UI-14, UI-16.

### Product decisions fixed for implementation

- Stop hint source: configured stop hotkey. If Caps Lock policy can stop current recording and is enabled, show `Release Caps Lock to stop` only for Caps-Lock-triggered hold recording. Otherwise show `Press {stopHotkeyDisplay} to stop`. If shortcut unassigned, show `Use menu bar to stop`.
- Wave color: retain feature and wire it to floating status waveform only. Immersive orange/coral stays fixed brand treatment.
- Canonical nouns: `Floating status`, `Immersive recording`, `Menu bar only`.
- Canonical states: Preparing model, Ready, Listening, Transcribing, permission/model/general failure.
- Stable island width: 300 points for every state. Keep AppKit host/window 360×70 unless rendered content clips; if changed, update host and window together.

### Owned files

- `Sources/MacApp/StatusView.swift`
- `Sources/MacApp/ImmersiveWaveformView.swift`
- `Sources/MacApp/WhisperApp.swift`
- `Sources/MacApp/SettingsView.swift`
- Prefer new pure helper in `Sources/Shared/` plus focused tests in `Tests/`

### Ordered edits

1. Create pure state presentation model, e.g. `DictationStatePresentation`:
   - visible title
   - optional detail
   - semantic role
   - status-item accessibility description
   - recovery action kind
   - bounded detail policy
2. Replace scattered `DictationState.label`, status icon descriptions, and immersive processing string with presentation model.
3. Do not put raw localized error text into compact label. Map known permission/model failures to short title; keep bounded detail with line limit/truncation and full accessibility value.
4. Inject recovery closure into `StatusView`: Retry model, Open Permissions, or Open Settings. Keep Abort only during cancellable transcription.
5. Inject stop-instruction string into `ImmersiveWaveformView`; remove hard-coded Caps Lock copy.
6. Track recording trigger in AppDelegate long enough to resolve truthful instruction. Do not change stop/start policy.
7. Make status-item image accessibility description state-specific.
8. Wire `useCustomWaveColor`/`waveColorHex` into floating waveform gradient. Invalid hex falls back to semantic active gradient. Do not apply to immersive view.
9. Rename settings/Main copy only:
   - `Overlay` → `Floating status`
   - `Show status indicator` → `Show floating status`
   - `Menu bar only mode (hide overlay)` → `Menu bar only`
   - supporting copy states exact effect
10. Add Settings toggle bound to existing `immersiveModeEnabled` key:
   - label `Immersive recording`
   - help `Shows immersive recording and transcribing treatment. It replaces floating status while active.`
11. Remove state-dependent width and spring resize. Use fixed 300-point island width and opacity-only content transition; honor Reduce Motion later in Slice 5.

### Tests

- Pure presentation tests for every `DictationState` case.
- Stop-hint matrix:
  - hotkey trigger + assigned stop shortcut
  - Caps Lock trigger + Caps Lock enabled
  - Caps Lock disabled
  - unassigned stop shortcut
- Wave-color resolver: enabled valid hex, enabled invalid hex, disabled.
- Error classification: accessibility, microphone/model, unknown.
- Width: all states render at 300 points; long error stays bounded to two lines.

### Visual checks

- Floating: loading, ready, recording, processing, permission error, long unknown error.
- Immersive: hotkey-triggered recording, Caps-Lock-triggered recording, processing.
- Settings General appearance/output section.
- Menu bar icon with VoiceOver description inspected.

### Stop conditions

- Stop if trigger tracking changes dictation lifecycle.
- Stop if permission recovery requires changing TCC settings. Opening correct System Settings pane is allowed only during implementation verification with explicit user approval.

## 5. Slice 3 — window and responsive layout repair

Addresses UI-02 and UI-04.

### Owned files

- `Sources/MacApp/WhisperApp.swift`
- `Sources/MacApp/MainView.swift`
- `Sources/MacApp/HistoryView.swift`
- `Sources/MacApp/VoiceMemosView.swift`
- `Sources/MacApp/SettingsView.swift`

### Ordered edits

1. Remove exact-size `.frame(width:height:)` from root views. Replace with `minWidth`/`minHeight` only where content truly needs it.
2. AppKit windows:
   - add `.resizable` to Settings, History, Voice Memos
   - keep default sizes close to current
   - set tested `contentMinSize`; remove `contentMaxSize`
   - History default must be at least view minimum; use one source of constants
3. Main: use adaptive grid driven by available width. Two columns at normal 760 width; one column below threshold. Preserve tile order.
4. Settings: keep tab content scrollable; verify Vocabulary split view minimums. Do not redesign settings navigation.
5. History header: allow search/filter controls to compress or wrap at minimum width. Never clip Clear action.
6. Voice Memos: sidebar/detail split remains; set practical minimum sidebar/detail widths and allow expansion.
7. Save no new persistent window geometry unless already supported. Restoration is separate scope.

### Resize matrix

| Window | Minimum | Default | Expanded |
|---|---:|---:|---:|
| Main | 640×520 | 860×640 | 1100×760 |
| Settings | 620×520 | 720×620 | 900×700 |
| History | 640×460 | 760×560 | 1100×760 |
| Voice Memos | 720×500 | 900×620 | 1200×800 |

Use exact minimum/default sizes. Escalate instead of silently changing contract.

### Verification

- Build/test commands from contract.
- Screenshots for every matrix cell.
- Increase macOS text size/accessibility setting only if already available; do not change system settings during automated pass.
- Confirm no clipped buttons, zero-width detail, or overlapping header fields.

## 6. Slice 4A — History interaction and deletion safety

Addresses UI-05 and History part of UI-07/UI-10.

### Owned files

- `Sources/MacApp/HistoryView.swift`
- `Sources/MacApp/WhisperApp.swift`
- Focused helper/tests if pure deletion policy extracted

### Ordered edits

1. Add explicit row selection using stable entry/correction IDs.
2. Make Copy and Correct visible for selected/focused row. Keep Paste and Delete in overflow/context menu unless width permits.
3. Replace 24×24 ad-hoc buttons with shared icon button style and minimum 32×32 targets.
4. Add keyboard commands/shortcuts where safe: Copy (`Cmd-C`) and Delete for selected row. Do not hijack text-field shortcuts.
5. Give every icon button label, hint, and help tooltip.
6. Route every row deletion and bulk clear through one typed pending destructive action. No delete callback mutates storage directly.
7. Add confirmation for every irreversible deletion. No fake undo:
   - `Delete transcription?` / `This removes this transcription from History. This cannot be undone.`
   - `Delete learned correction?` / `Whisper will no longer apply this correction. This cannot be undone.`
   - `Clear all History?` / `This removes {count} transcriptions. This cannot be undone.`
   - `Clear all Corrections?` / `This removes {count} learned corrections. This cannot be undone.`
8. Change menu-bar `clearHistory()` to show `NSAlert` before mutation. Buttons: `Cancel`, `Clear History`.
9. Announce copy/fallback-to-clipboard result without changing stored data.

### Verification

- Empty, filtered-empty, populated, correction sheet.
- Pointer, keyboard-only, VoiceOver labels.
- Clear cancellation preserves item count; confirmation clears correct surface only.
- Search field still receives normal copy/delete keys.

## 7. Slice 4B — Voice Memo controls and selection

Addresses UI-06 and Voice Memo part of UI-07/UI-10.

### Owned files

- `Sources/MacApp/VoiceMemosView.swift`
- `Sources/MacApp/MainView.swift`
- Focused tests only for extracted pure policy

### Ordered edits

1. Preserve current SwiftUI `onChange` warning cleanup.
2. Replace row `onTapGesture` selection with Button or native selectable-list semantics. Keep nested play/menu controls functional; avoid nested Button invalidity by separating row selection region.
3. Add explicit selected and keyboard-focus visuals using design tokens.
4. Record controls in Main and Voice Memos receive:
   - visible `Record`/`Stop Recording` label where space allows
   - explicit accessibility label/value/hint
   - semantic active accent; danger only for destructive actions
   - 44×44 minimum target
5. Keep duration and waveform as status, not click target.
6. Add Delete Memo confirmation with memo title/date. Stop playback before deletion only through existing manager API.
7. Ensure overflow actions keep Rename, Export Audio, Re-transcribe, Auto-Transcribe toggle, Delete.

### Verification

- Empty/list/detail/recording/transcribing/playback/no transcript/auto-off.
- Arrow-key or list keyboard selection.
- Play control does not also change selection unexpectedly unless product behavior explicitly intends it.
- Delete cancel leaves audio/transcript intact.

## 8. Slice 5 — motion and accessibility

Addresses UI-08 and UI-15; completes accessibility portions of UI-05/UI-06/UI-13/UI-14.

### Owned files

- All UI files touched by prior slices. One sequential agent only.

### Ordered edits

1. Read `@Environment(\.accessibilityReduceMotion)` in Status and Immersive SwiftUI views.
2. Reduced-motion behavior:
   - no traveling scanline
   - no pulsing dots
   - waveform updates from real level only at reduced cadence or static level representation
   - opacity transition ≤150 ms or immediate
3. AppKit ASCII renderer: expose static/reduced-rate mode or keep inactive until Slice 6 decision. Never run decorative 30 fps timer while hidden/off-window.
4. Keep immersive decoration `accessibilityHidden(true)`, but post/offer equivalent recording and processing status through status item or non-decorative accessibility element. Avoid duplicate repeated announcements.
5. Add labels/hints/values to all icon-only controls and hotkey recorder.
6. Verify focus ring visibility against custom cards and selected rows.
7. Ensure status/error meaning includes text/icon, never color alone.
8. Audit target sizes and `.help` tooltips.

### Verification

- VoiceOver walkthrough: Main → Settings → History → Voice Memos → live state.
- Keyboard-only walkthrough.
- Reduce Motion off/on recording→processing capture.
- Timer/log inspection confirms decorative loops stop or reduce.

## 9. Slice 6 — dead visual paths

Addresses UI-17.

### Product decision gate

Default recommendation: keep `ImmersiveWaveformView` as sole immersive recording/processing surface; remove unreachable processing bar and Mac ASCII overlay only after repo-wide call/reference proof and architecture audit agreement.

### Owned files

- `Sources/MacApp/ASCIIOverlayView.swift`
- `Sources/MacApp/ASCIICanvasView.swift`
- `Sources/MacApp/ImmersiveProcessingView.swift`
- `Sources/MacApp/WhisperApp.swift`
- Project file only if source removal requires target cleanup

### Ordered work

1. `rg` every type/function reference and inspect Xcode target membership.
2. Prove runtime reachability or non-reachability for:
   - `ASCIIOverlayView`
   - `ASCIICanvasView`
   - `showProcessingBar`
   - `ImmersiveProcessingView`
3. If unreachable and architecture audit agrees, remove types, setup functions/windows, and target references in one bounded patch.
4. If retained, wire exactly one explicit state path and add Reduce Motion behavior. Do not keep dormant alternative styling.
5. Build/test and compare app binary warnings.

### Stop conditions

- Stop if any path is referenced by iOS/shared code, tests, or pending architecture remediation.
- Stop if removal changes visible behavior. Escalate product decision.

## 10. Global verification checklist

- [ ] `git diff --check`
- [ ] `swift test`
- [ ] `bash ./scripts/build_xcode_mac.sh`
- [ ] zero new compiler warnings
- [ ] no changed AppStorage keys without migration
- [ ] no changed dictation/audio lifecycle outside named task
- [ ] no changed persistence schema
- [ ] no iOS regression
- [ ] Main/status/settings/history/memos/immersive capture matrix complete
- [ ] keyboard-only pass
- [ ] VoiceOver labels/status pass
- [ ] Reduce Motion pass
- [ ] all UI-01…UI-17 ledger rows linked to proof

## 11. Manager dispatch rule

Before each Luna dispatch:

1. Re-read Architecture audit final artifact.
2. Re-run Git status/diff and note new overlapping edits.
3. Send only one owned file set to one Luna task.
4. Require task to stop on collision, not resolve by overwrite.
5. Review diff locally before next dispatch.
6. Update ledger with evidence, not agent claim alone.
