# Whisper UI/UX Audit

Date: 2026-07-21
Scope: macOS UI, read-only audit
Direction: dark UI; immersive orange/coral treatment as visual north star; all features preserved

## Executive summary

Whisper has strong live-capture identity inside Immersive Mode, but rest of app uses separate purple/blue glass-dashboard language. Biggest issue is not polish. Biggest issue is state truth: immersive UI always says `CAPS LOCK to stop`, even when Caps Lock control is disabled and stop shortcut is configurable.

Best path: six small slices. First create semantic design foundation. Next fix live-state truth. Then repair window contracts, controls, accessibility/motion, and dead visual paths. No giant rewrite.

Top findings:

1. **P0 — false stop instruction:** Immersive Mode hard-codes Caps Lock.
2. **P1 — broken size contract:** History view asks for 680×500 inside locked 600×450 AppKit window.
3. **P1 — inert preference:** custom wave color is stored but never rendered.
4. **P1 — weak keyboard/accessibility paths:** hidden History actions, gesture-only memo selection, icon-only record controls, no Reduce Motion variants.
5. **P2 — split visual language:** purple/blue shared design system conflicts with orange/coral immersive UI and scattered red/green/blue feature colors.

## Evidence and screenshot status

Computer Use found running `com.quincy.whisper` processes and activated repo-built `Whisper.app`. Product UI capture timed out when addressed by app path, app name, bundle ID, and SystemUIServer. App exposes no normal launch window; source confirms `Settings` scene plus AppDelegate-owned menu item/window entry points. Native `screencapture` also lacked display capture access. No permission or system setting was changed.

Only captured frame is environment evidence, not product UI evidence:

![Whisper audit capture environment](AuditScreenshots/capture-environment.jpeg)

No prior UI screenshots exist in repo. Screenshot-backed product review remains blocked until operator opens status item or grants existing Codex capture process access. Findings below use source-backed state inspection. Capture matrix at end gives exact follow-up.

## View and state inventory

| Surface | Primary source | States / content | Capture priority |
|---|---|---|---|
| Menu bar/status item | `Sources/MacApp/WhisperApp.swift` `AppDelegate` | loading, ready, recording, processing, error; Recent empty/populated | High |
| Floating status island | `Sources/MacApp/StatusView.swift` | loading, ready, recording waveform, processing/abort, error, last text | High |
| Main dashboard | `Sources/MacApp/MainView.swift` | Dictation, Voice Memos, History, Accuracy | High |
| Settings | `Sources/MacApp/SettingsView.swift` | General, Model, Vocabulary, Permissions | High |
| History | `Sources/MacApp/HistoryView.swift` | empty, filter-empty, populated history, learned corrections | High |
| Correction editor | `Sources/MacApp/CorrectionLearningEditorView.swift` | no selection, edited result, detected changes, saved | Medium |
| Voice Memos | `Sources/MacApp/VoiceMemosView.swift` | empty, list/detail, recording, transcribing, playback, rename, no transcript, auto-off | High |
| Immersive overlay | `Sources/MacApp/ImmersiveWaveformView.swift` | recording waveform, processing pulse | Highest |
| Processing bar | `Sources/MacApp/ImmersiveProcessingView.swift` | 60 fps scanline; currently unreachable | Low |
| Shortcut recorder | `Sources/MacApp/HotkeyRecorderView.swift` | idle, listening, invalid modifier | Medium |
| ASCII overlay | `Sources/MacApp/ASCIIOverlayView.swift`, `ASCIICanvasView.swift` | recording fire, processing noise; currently unused | Low |

## Findings mapped to code

| Priority | Finding | Exact view/file | User impact | Change risk |
|---|---|---|---|---|
| P0 | `CAPS LOCK to stop` is always shown. Caps Lock mode defaults off; stop hotkey is configurable. | `ImmersiveWaveformView.swift:94`; `SettingsView.swift:156`; `SettingsView.swift:185`; `WhisperApp.swift:154` | False instruction during live capture; loss of control/trust. | Low if hint becomes injected display string. |
| P1 | History root fixes 680×500 while AppKit locks 600×450. | `HistoryView.swift:35`; `WhisperApp.swift:623` | Clipping, compression, broken layout contract. | Low. Align minimum/initial size; allow resize. |
| P1 | Custom wave color preference has writer but no consumer. | `SettingsView.swift:15`; `SettingsView.swift:252`; `SettingsView.swift:366` | Setting appears broken. | Medium. Decide wire into status waveform or remove preference. Product decision. |
| P1 | Settings, History, Voice Memos are hard-locked; Main grid remains two columns. | `WhisperApp.swift:595`; `WhisperApp.swift:623`; `WhisperApp.swift:644`; `MainView.swift:37` | Poor scaling, localization, accessibility text size. | Medium. Layout regression risk across panes. |
| P1 | History row actions exist only on hover; 24×24 targets. | `HistoryView.swift:296`; `HistoryView.swift:410` | Low discoverability; weak keyboard/VoiceOver use. | Medium. Preserve actions while changing presentation. |
| P1 | Voice memo row selection uses `onTapGesture`; record buttons are unlabeled custom circles. | `VoiceMemosView.swift:153`; `VoiceMemosView.swift:240`; `MainView.swift:124` | Unclear affordance, missing focus/keyboard semantics. | Medium. Use Button/selection semantics without changing callbacks. |
| P1 | Clear History and item deletion lack consistent confirmation/undo. | `HistoryView.swift:96`; `WhisperApp.swift:1389`; `VoiceMemosView.swift:313` | Accidental data loss. | Medium. Confirmation and undo policy needs product choice. |
| P1 | Continuous Timeline/Canvas animation ignores Reduce Motion. | `StatusView.swift:130`; `ImmersiveWaveformView.swift:149`; `ImmersiveWaveformView.swift:185`; `ImmersiveProcessingView.swift:10`; `ASCIICanvasView.swift:145` | Motion sensitivity, CPU/battery load. | Medium. Static/reduced-rate variants needed. |
| P2 | Shared palette is purple/blue while immersive/status uses orange/yellow and features scatter red/green/blue. | `DesignSystem.swift:7`; `StatusView.swift:112`; `ImmersiveWaveformView.swift:25`; `HistoryView.swift:273` | No predictable hierarchy or brand continuity. | Low with semantic aliases; medium during adoption. |
| P2 | Status language conflicts: `Processing...`, `Transcribing…`, `Loading model...`, `Listening...`. | `StatusView.swift:235`; `ImmersiveWaveformView.swift:197` | Unclear model state and timing. | Low. Central state copy map. |
| P2 | `Overlay`, `status indicator`, `floating status overlay`, `Menu bar only mode`, `Immersive Mode` overlap. | `MainView.swift:89`; `SettingsView.swift:223`; `WhisperApp.swift:550` | Settings hard to predict. | Low copy risk; medium if setting structure changes. |
| P2 | Error text is arbitrary length inside narrow status island; no recovery action. | `StatusView.swift:49`; `StatusView.swift:235` | Truncation; user cannot fix permission/model failure. | Medium. Error classification and routing needed. |
| P2 | Status item accessibility description never reflects state. | `WhisperApp.swift:231`; `WhisperApp.swift:1198` | VoiceOver gets visual icon change only. | Low. |
| P2 | Immersive surface is hidden from accessibility with no equivalent announcement. | `ImmersiveWaveformView.swift:22` | VoiceOver misses recording/processing transitions. | Low/medium. Keep decoration hidden; announce state elsewhere. |
| P2 | Floating island jumps between 140, 180, and 320 widths with spring transition. | `StatusView.swift:49` | Distracting motion, shifting scan target. | Low. Use stable width bands/reduced motion. |
| P3 | ASCII overlay and processing bar appear disconnected from runtime path. | `ASCIIOverlayView.swift:31`; `WhisperApp.swift:1323` | Maintenance cost, conflicting future visual direction. | Low after product decision and reference search. |

## Visual hierarchy direction

Immersive Mode becomes anchor, not full-screen template copied everywhere.

- Canvas stays near-black, quiet, low chroma.
- Orange/coral marks live capture, primary action, focused emphasis.
- Processing uses warmer amber motion, not unrelated blue.
- Red reserved for destructive action and error, not normal recording identity.
- Green reserved for confirmed success/permission granted.
- Cards use depth through surface value and stroke, not many gradients.
- Main window keeps dashboard features but gives Dictation one clear primary position.

## Proposed design system

### Color tokens

| Token | Suggested value | Use |
|---|---:|---|
| `canvas` | `#0B0B0D` | Window background |
| `surface` | `#131316` | Standard pane/card |
| `surfaceRaised` | `#1A1A1F` | Floating card, popover |
| `surfaceInset` | `#09090B` | Waveform/transcript wells |
| `textPrimary` | `#F5F3F1` | Main content |
| `textSecondary` | `#A9A5A1` | Supporting copy |
| `textTertiary` | `#74716E` | Metadata; avoid for critical copy |
| `strokeSubtle` | white 10% | Card boundaries |
| `strokeStrong` | white 20% | Focused/selected boundaries |
| `accentActive` | `#FF6A32` | Capture, primary action, focus |
| `accentActiveBright` | `#FF9A62` | Waveform/highlight |
| `processing` | `#F6A43A` | Transcribing/model work |
| `success` | `#55C58A` | Completed/granted |
| `warning` | `#E8B44C` | Recoverable caution |
| `danger` | `#F05D62` | Error/destructive only |
| `info` | `#75A7E8` | Neutral informational state |

Validate contrast in rendered screens before shipping. Keep macOS semantic foreground colors where they outperform fixed values.

### Typography

- `display`: 26 semibold — main product title only.
- `title`: native `.title3.weight(.semibold)` — window/section title.
- `body`: native `.body` — content and controls.
- `label`: native `.callout.weight(.medium)` — button/row label.
- `metadata`: native `.caption` — time, model, counts.
- `micro`: `.caption2.weight(.semibold)` — uppercase chip only; never core instruction.
- Monospaced type only for shortcuts, model identifiers, waveform/ASCII, correction comparison.

### Geometry

- Spacing: 4, 8, 12, 16, 24, 32.
- Control height: 32 compact, 36 standard, 44 primary/record.
- Radius: 8 controls, 12 rows, 16 cards, 24 immersive capsule.
- Minimum pointer target: 32×32 desktop; 44×44 for record, stop, destructive, and touch-adjacent controls.
- Windows: resizable with tested minima; content adapts before clipping.

### Shared components

| Component | First consumers | Contract |
|---|---|---|
| `WhisperWindowHeader` | Main, History, Voice Memos, Settings | title, subtitle, trailing actions |
| `WhisperCard` | Main tiles, Voice Memo detail | surface level, selected/focused state |
| `WhisperPrimaryAction` | Dictation, memo recording, correction save | label + icon + keyboard hint + busy state |
| `WhisperIconButton` | History/memo row actions | explicit accessibility label, 32/44 target |
| `WhisperStatusChip` | History, model, permission | icon + label; never color-only |
| `WhisperEmptyState` | History, filters, Voice Memos | icon, title, explanation, optional action |
| `WhisperRowActions` | History, Corrections, Voice Memos | visible on selection/focus; overflow for destructive |
| `WhisperStateCopy` | status island, immersive, menu item | one canonical label and accessibility value per state |

## Interaction and motion rules

1. One clear primary action per surface.
2. Every pointer action has keyboard/VoiceOver path.
3. Destructive actions live in overflow/context menu unless they are current task; confirm irreversible bulk actions.
4. Hover may reveal extra detail, never sole access to core action.
5. Recording uses orange/coral plus icon/text. Error uses danger plus icon/text. Never state by color alone.
6. State transitions: 150–220 ms ease; immersive expansion up to 280 ms.
7. `accessibilityReduceMotion`: replace traveling/pulsing effects with opacity or static level meter; stop decorative 30/60 fps loops.
8. Status island should hold stable width during recording→processing sequence.
9. Focus ring remains system-visible; custom cards do not suppress it.
10. Error state gives plain cause plus one recovery action: Retry, Open Permissions, or Open Settings.

## Copy model

Canonical live states:

| Internal state | Visible label | Supporting text/action |
|---|---|---|
| loading | Preparing model | Model name when useful; Cancel only if supported |
| ready | Ready | Start Dictation + shortcut |
| recording | Listening | `Press {configured stop shortcut} to stop` |
| processing | Transcribing | Abort only while operation is cancellable |
| error(permission) | Microphone/Accessibility access needed | Open Permissions |
| error(model) | Model could not load | Retry / Model Settings |
| error(other) | Dictation failed | Short cause + Retry |

Recommended setting nouns:

- `Floating status` — small always-on-top island.
- `Immersive recording` — full-screen glow/capsule treatment.
- `Menu bar only` — hides floating status; exact effect stated below toggle.

## Incremental delivery slices

### Slice 1 — design foundation

Files: `Sources/Shared/DesignSystem.swift`, small adoption in `MainView.swift` and `StatusView.swift`.
Change: semantic tokens, type/spacing/radius primitives, cards/buttons.
Risk: low.
Acceptance: features unchanged; build passes; main ready/recording and status ready/recording screenshots approved.

### Slice 2 — live-state truth

Files: `StatusView.swift`, `ImmersiveWaveformView.swift`, `WhisperApp.swift`, possibly settings display helper.
Change: configured stop hint, canonical state copy, classified recovery actions, dynamic status-item accessibility.
Risk: low/medium.
Acceptance: hold/toggle/Caps Lock configurations show truthful instruction; loading/processing/error captures approved.

### Slice 3 — window and layout contracts

Files: `WhisperApp.swift`, `MainView.swift`, `HistoryView.swift`, `VoiceMemosView.swift`, `SettingsView.swift`.
Change: repair History mismatch, resizable windows/minima, adaptive Main columns, scroll-safe dense settings.
Risk: medium.
Acceptance: minimum/default/expanded window screenshots; no clipping at larger text setting.

### Slice 4 — control consistency

Files: Main, History, Voice Memos, Correction Editor.
Change: shared primary/icon/row controls; keyboard selection; visible focused actions; deletion policy.
Risk: medium.
Acceptance: all existing callbacks/features preserved; keyboard-only walkthrough passes.

### Slice 5 — motion and accessibility

Files: Status, Immersive, Voice Memos, History, Hotkey Recorder, ASCII renderer if retained.
Change: Reduce Motion, labels/hints/values, state announcements, target sizes, contrast verification.
Risk: medium.
Acceptance: VoiceOver state walkthrough; Reduce Motion screen recording; keyboard focus audit.

### Slice 6 — visual-path cleanup

Files: `ASCIIOverlayView.swift`, `ASCIICanvasView.swift`, `ImmersiveProcessingView.swift`, `WhisperApp.swift`.
Change: choose keep/wire/remove for unused paths.
Risk: low after product decision.
Acceptance: one authoritative recording and processing presentation per mode.

## Screenshot capture matrix

Capture at default size plus minimum supported size. Use sample data without deleting or changing user data.

- Main: ready, recording, loading, error.
- Menu bar: ready, recording, processing, error; Recent empty and populated.
- Floating status: ready, recording at quiet/loud level, processing, long error.
- Settings: General, Model, Vocabulary empty/populated/selection, Permissions granted/denied.
- History: empty, search miss, populated, learned corrections, correction sheet.
- Voice Memos: empty, list selected, detail playback, recording, transcribing, no transcript, auto-transcribe off.
- Immersive: recording and processing, with Reduce Motion on/off.

## Exact next prompt

> In `/Users/quincyobeng/Documents/Code/AI/Claude/Voice-v2`, implement Slice 1 only from `Design/WHISPER_UI_UX_AUDIT_2026-07-21.md`. Read `NEXT.md` if present and inspect Git status first. Preserve unrelated work. Expand `Sources/Shared/DesignSystem.swift` with dark semantic surface/text/stroke/status colors, orange/coral active accent, spacing/radius/type tokens, and reusable card/button styling. Replace only obvious shared raw styling in `Sources/MacApp/MainView.swift` and `Sources/MacApp/StatusView.swift`. Do not change features, copy/state behavior, window sizing, AppKit lifecycle, settings behavior, iOS screens, or unused visual paths. Build, then capture and visually inspect main ready/recording plus floating status ready/recording. Stop after verification; no commit or push.
