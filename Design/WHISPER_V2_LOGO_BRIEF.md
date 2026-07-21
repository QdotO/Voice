# Whisper v2 Logo Brief

## Goal
Create a logo system for Whisper v2 that feels native to the app's existing visual language instead of introducing a generic microphone mark.

## Source Motifs From The App
- `Sources/MacApp/StatusView.swift`
  - three-line monospaced ASCII wavefield
  - character set built from `.:/\\+*#RWDLS`
  - warm orange-to-gold gradient during active dictation
- `Sources/MacApp/ASCIICanvasView.swift`
  - dense ASCII texture
  - fire palette moving from ember red to yellow-white
- `Sources/MacApp/ImmersiveWaveformView.swift`
  - narrow horizontal waveform bars
  - strong orange-to-yellow progression
- `Sources/MacApp/ImmersiveProcessingView.swift`
  - scanning beam
  - ASCII trail behind motion

## Direction Chosen
- Primary icon: a bold `W` silhouette filled with ASCII wave rows.
- Motion reference: a vertical scan-beam crossing the `W`.
- Color system: black/charcoal base with ember orange, gold, and near-white highlights.
- Shape language: rounded-square app icon plus a capsule-like inner field, echoing the status overlay.

## Deliverables
- `Design/WhisperV2-AppIcon.svg`
  - square icon candidate for export to app-icon sizes
- `Design/WhisperV2-Logo.svg`
  - horizontal lockup for presentations, readme, landing pages, and release notes
- `Design/export_app_icon_assets.sh`
  - reproducible export script for the iOS app icon set, a generated macOS `.iconset`, and a packaged `.icns`

## Why This Fits v2
- It reuses the product's strongest existing identity: ASCII audio visualization.
- It feels offline, technical, and signal-driven rather than assistant-branded.
- It stays compatible with the smaller v2 scope: dictation, memos, history, and correction quality.

## Integration Status
- The iOS app icon catalog has been regenerated from the new SVG source.
- A macOS `.iconset` source folder is now generated in `Design/Generated/WhisperV2.iconset`.
- A packaged macOS icon file is generated in `Design/Generated/WhisperV2.icns`.
- `scripts/build_xcode_mac.sh` now builds the `WhisperMac` Xcode target into a repo-local `.xcode-build` directory and uses a repo-local package clone directory so package resolution remains stable inside the git worktree.
- `build.sh` is now a thin convenience wrapper around the Xcode build path; it no longer assembles `Whisper.app` manually.
- The macOS runtime menu bar icon was intentionally left stateful for now because it communicates recording, processing, and error states better than a static logo.
