# Whisper Remediation Execution Board

Date: 2026-07-22
Branch: `codex/correction-vocabulary-cleanup` at `c209d56`
Mode: authorized release implementation; serialized bounded writers

## Decisions authorized 2026-07-22

- Remove all iOS app and custom-keyboard support. Delete only confirmed iOS-only paths and references; preserve shared macOS code.
- Direct macOS distribution. Prepare Developer ID signing, hardened-runtime, packaging, and notarization-ready configuration. No credential changes, certificate creation, notarization submission, or external release yet.
- Replace manual tabbed Settings `NSWindow` with native SwiftUI `Settings` scene. Preserve keys, sections, persistence, deep links, menu/menu-bar entry points, and visible features.
- Integrate intended audit/remediation scope, commit intentionally, merge to `main` after checks and repository policy review, then push. No force push, rebase, reset, or clean.

## Reconciliation result

Current code and Git diff supersede older thread summaries that said UI rollout had not started.

- Architecture ledger ARC-01 through ARC-17 and ARC-22 is implemented in current uncommitted worktree. Code markers, focused tests, project settings, and ledger evidence are present.
- UI-01 through UI-17 code is implemented in current uncommitted worktree. Semantic dark/coral design tokens, shared controls, truthful dictation presentation, responsive layout, destructive-action policy, Reduce Motion, and accessibility work are present. Screenshot, keyboard-only, VoiceOver, and Reduce Motion proof remains open.
- Immersive spinner/dead processing path is removed. Caps Lock stop policy and truthful stop copy are present.
- ARC-17 is already isolated and complete: signal-safe crash path, user Logs location, subprocess harness.
- ARC-19 configuration work is complete for macOS direct-distribution readiness; iOS configuration was subsequently removed.
- ARC-22 Swift 6 migration is already complete in Package.swift/Xcode settings. Do not dispatch another migration.
- Three tracked visual files are intentionally deleted. Their runtime paths were removed under completed dead-path cleanup.

Current integration risk is high: 42 tracked files changed, 29 untracked paths, 3 tracked deletions. Work spans architecture, persistence, concurrency, UI, tests, project files, plists, and this execution board without integration commit boundaries. Do not start another writer until full verification finishes. Do not rebase, reset, stash, clean, or overwrite.

## Active execution board

| State | Owner | Scope | Dependencies / stop rule |
|---|---|---|---|
| Complete | Luna-high integration verifier — task `019f89df-1786-7872-ae68-a602683fcea1` | 338 Swift tests, crash harness, Mac/iOS/keyboard builds, and diff check all pass | Baseline safe for decision gate; not release/merge ready. |
| Complete | Terra-high ARC-19 config sync — task `019f89e3-931b-7bb2-ae92-d25f2c09bf8e` | `project.yml` now matches verified iOS 17/no-full-screen generated configuration | Isolated XcodeGen output verified; iPhone-only target preserved. |
| Complete / blocked on UI access | Luna-high screenshot verifier — task `019f89dd-ce78-7d32-8a67-9e1107429035` | Existing UI screenshot and interaction-state proof only | Blocker note/manual checklist written; no TCC/system setting changes. |
| Stopped | Terra-high UI Slice 1 — task `019f89dd-d061-7f21-8cfc-e640260b9115` | Duplicate design-foundation request | Collision confirmed; requested outcomes already present. No files changed. |
| Holding | Release manager — task `019f89dd-cbdc-7062-a141-ec7d9d45d3d7` | Review verification, keep ownership map, handoff decisions | No broad code edits. No new writer before baseline result. |
| Complete | Luna-high iOS removal inventory — task `019f8a40-41fe-74d3-a083-cc5e6ceacad8` | Exact deletion/edit/preservation ownership map | Read-only inventory closed. |
| Complete | Luna-high distribution inventory — task `019f8a40-444f-76f0-9daf-0694ef01fca1` | Existing signing, entitlements, artifact, hardened-runtime, packaging readiness | Read-only inventory closed. |
| Complete | Luna-high Settings inventory — task `019f8a40-463f-7e92-9155-7c2e86639c7a` | Native Settings scene migration map and deep-link preservation | Read-only inventory closed. |
| Complete | Terra-high iOS removal writer — task `019f8a43-1f59-7bf3-8fc6-8adeb6a0d347` | Deleted confirmed 21-file `iOS/` tree; removed iOS platform/targets/references; trimmed icon exporter | 338 tests, crash harness, Mac build, single-target Xcode graph pass. |
| Complete | Terra-high native Settings writer — task `019f8a47-173b-7902-b018-9fda5dd3544d` | Replaced manual Settings `NSWindow` with existing native SwiftUI `Settings` scene; preserved routes/state | 338 tests, crash harness, Mac build pass; manual route/window check remains. |
| Complete | Terra-high direct-distribution writer — task `019f8a4c-5ead-7460-aced-cc3abed127d4` | Hardened runtime, required microphone entitlement, direct packaging/notarization-ready flow | 338 tests, crash harness, unsigned Release archive, validation ZIP pass. Signed release blocked by missing identity. |
| Complete | Luna-high final integration reviewer — task `019f8a51-53cc-7260-9f27-61d2fbdcc8f5` | Full diff/path-scope review, clean verification, packaging/signing truth, staging manifest | Internal blockers fixed; safe for intentional staging/commit. |

## Remaining work, ordered

1. **ARC-19 source-of-truth sync — complete** — `project.yml` now declares iOS 17 and omits obsolete `UIRequiresFullScreen`; isolated XcodeGen output matches current generated project/plist state.
2. **Visual proof** — finish screenshot task if existing permission permits. Screenshot, keyboard-only, VoiceOver, and Reduce Motion checks remain open. If blocked, keep explicit manual capture checklist; do not change Screen Recording or Accessibility settings.
3. **Remove iOS support — complete** — 21 tracked iOS-only paths and every live target/platform/reference removed.
4. **Native Settings scene — complete** — manual window removed; native route/deep links preserved.
5. **Direct distribution readiness — complete locally** — hardened runtime, entitlement, packaging flow, and unsigned validation artifact verified. Signed/notarized artifact awaits credentials.
6. **Integration review — complete** — path-scope review, full Swift/macOS tests/build, crash harness, packaging/signing truth, and staging manifest verified.
7. **Publish** — stage only intended Whisper release paths, create intentional commits, push branch, use draft PR when GitHub auth permits, merge `main` only after checks/policy allow, push `main`.
8. **ARC-21 deferred** — dictation-session extraction remains outside current goals unless needed solely to preserve Settings migration behavior.
9. **DEAD-05 deferred** — public schema/API compatibility decision remains outside current goals.

## File ownership gates for future work

- UI slices remain serialized 1 → 2 → 3 → 4A/4B → 5 → 6. Current worktree already contains all slices; any repair must preserve that order conceptually and use one writer for overlapping files.
- ARC-18 is closed by authorized removal of all iOS app/keyboard support.
- ARC-19 owns project, plists, resources, signing/distribution configuration only.
- ARC-20 owns window lifecycle and AppDelegate window extraction only.
- ARC-21 owns dictation orchestration extraction only after ARC-20.
- ARC-17 files stay closed unless integration verification finds a reproducible crash-harness failure.

## Release gate

Pre-removal baseline verification passed 338 tests plus macOS/iOS/keyboard builds. Final verification below supersedes platform scope.

Final macOS-only verification after iOS removal:

- 338/338 Swift tests pass; crash harness passes.
- Xcode graph contains only `WhisperMac`; fresh unsigned Debug build and Release archive pass.
- Native Settings private-selector fallback removed; public `OpenSettingsAction` queue handles early requests.
- Hardened Runtime on, App Sandbox off, audio-input entitlement configured, Apple Events declaration removed, productivity category set.
- Generated caches and `dist/` ignored; `git diff --check`, plist/entitlement lint, and script syntax pass.
- Unsigned validation ZIP is structurally valid but not distributable.

External blockers: zero valid Developer ID identities, no notarization credential/profile, manual Settings/UI/VoiceOver/Reduce Motion checks incomplete, GitHub CLI token invalid.

Commits, merge to `main`, and pushes are authorized after full validation and scope review. Force push, rebase, reset, clean, permission/system changes, credential changes, notarization submission, and final external distribution remain prohibited.
