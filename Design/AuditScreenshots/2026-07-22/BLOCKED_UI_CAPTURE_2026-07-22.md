# Whisper UI capture blocker

Date: 2026-07-22
Scope: read-only UI capture and interaction-state verification for Slice 1/2

## Result

No product UI screenshots captured. Existing `Design/AuditScreenshots/capture-environment.jpeg` remains environment evidence only.

## Exact access blocker

- `sky.get_app_state({ app: "com.quincy.whisper" })` failed because multiple repo-built Whisper apps share bundle identifier.
- `sky.get_app_state({ app: "/Users/quincyobeng/Documents/Code/AI/Claude/Voice-v2/Whisper.app" })` timed out with Computer Use server error `-10005: timeoutReached`.
- Retry through display name `Whisper` also timed out with `-10005: timeoutReached`.
- `sky.list_apps()` showed Whisper running, but did not expose a usable distinct target for this repo app.
- `sky.get_app_state({ app: "SystemUIServer" })` did not return; pending probe terminated under manager stop rule.
- Prior audit records native `screencapture` display access unavailable. No TCC, permission, or system setting changes attempted.

Manager stop rule: no further app automation, app launch, permission/TCC request, or system-setting change.

## Manual capture checklist

Run with existing repo-built Whisper app and no data-changing actions. Save files in this directory with descriptive names.

### Screenshots

- [ ] Menu bar/status item: ready
- [ ] Menu bar/status item: recording, only if naturally visible without starting dictation
- [ ] Menu bar/status item: processing/error, only if naturally visible
- [ ] Open Main from status item; capture ready state
- [ ] Open Settings; capture General, Model, Vocabulary, Permissions
- [ ] Open History; capture empty or existing state without deleting/editing data
- [ ] Open Voice Memos; capture empty/list/detail state without recording, renaming, exporting, or deleting
- [ ] Immersive waveform: recording and processing only if naturally accessible
- [ ] Record whether any state shows false `CAPS LOCK to stop` copy when Caps Lock control is disabled or another stop shortcut is configured
- [ ] Record whether status labels use canonical `Ready`, `Listening`, `Transcribing`, and recovery copy from Slice 2 plan

### VoiceOver

- [ ] Main: Dictation primary action has label, value, hint, and focus path
- [ ] Status item: accessible label/value changes across ready, recording, processing, and error
- [ ] Settings: controls expose current values and permission state
- [ ] History: row selection and Copy/Correct/Delete actions have keyboard and VoiceOver paths; hover is not sole access
- [ ] Voice Memos: row selection, play, record/stop, overflow, and delete expose labels and state
- [ ] Immersive recording/processing state has an equivalent accessible status; decorative waveform may remain hidden

### Keyboard-only

- [ ] Navigate Main, Settings, History, and Voice Memos without pointer
- [ ] Trigger primary dictation action without inserting text into another app
- [ ] Reach History row actions without hover
- [ ] Select Voice Memo row and reach play/overflow controls without gesture-only selection
- [ ] Focus record/stop controls and verify visible focus ring and target size
- [ ] Verify configured stop shortcut text matches actual shortcut; do not change settings during audit

### Reduce Motion

- [ ] With Reduce Motion off, capture recording and processing transitions if naturally accessible
- [ ] With Reduce Motion on, capture same states only if setting already enabled; do not change system setting during automated pass
- [ ] Confirm traveling scanline/pulsing decorative loops stop or reduce, while state meaning remains visible
- [ ] Confirm status island expansion uses opacity/static level behavior instead of repeated motion where applicable

## Missing evidence

Product UI screenshots, VoiceOver traversal, keyboard-only traversal, and Reduce Motion visual proof remain unavailable. Slice 1/2 visual approval remains blocked pending operator capture or restored display/UI automation access.
