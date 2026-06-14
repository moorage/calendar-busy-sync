# Dual-Platform App Store Connect Refresh

## Purpose / Big Picture

Refresh both App Store Connect platform records from the current workspace by producing fresh macOS and iOS App Store exports, uploading the newest packages, and reattaching the latest valid builds so the submission state reflects the code checked out locally.

This pass should reuse the existing repo release harness instead of inventing new release commands. The work is operational rather than feature development, but it still needs a durable record because it spans two Apple platforms, remote App Store Connect state, and build/upload prerequisites that can fail outside the codebase.

## Progress

- [x] 2026-04-23T05:50Z inspect the repo release docs, active submission plans, and existing archive/upload helpers for both platforms
- [x] 2026-04-23T05:50Z create a dedicated ExecPlan for the dual-platform refresh run so build/upload outcomes and blockers are recorded in-repo
- [x] 2026-04-23T05:50Z archive the latest macOS build from the current workspace and confirm the export succeeds
- [x] 2026-04-23T05:57Z capture the first upload blocker: App Store Connect rejects build number `2` because that bundle version was already used
- [x] 2026-04-23T06:04Z bump the shared project build number to `3` and rerun macOS plus iOS archive/upload from the updated workspace
- [x] 2026-04-23T06:04Z archive and upload the latest iOS build from the current workspace
- [x] 2026-04-23T06:04Z refresh App Store Connect metadata/build attachments for both platform records and record the resulting build ids

## Surprises & Discoveries

- 2026-04-23: the repo already has completed one-off App Store submission passes for macOS and iOS, but there is not yet an active operational plan for rerunning both refreshes together from the current workspace.
- 2026-04-23: `scripts/upload-appstore` supports both `macos` and `ios`, so the same verified export-and-upload path can be reused for both platforms without local code changes.
- 2026-04-23: the first macOS upload attempt failed remotely even though local archive/export succeeded, because `CURRENT_PROJECT_VERSION = 2` matches the previously uploaded App Store build number and Apple requires a higher `CFBundleVersion` for the next upload.
- 2026-04-23: final unit-test validation surfaced a separate compile issue in the hosted test target because `MenuPresentationSnapshot` was declared `private`; making it internal fixed the compile failure, but the hosted macOS XCTest runner still went quiet afterward and had to be interrupted.

## Decision Log

- 2026-04-23: create one new operational ExecPlan for this refresh instead of reopening the older platform-specific submission plans, because this task is a rerun against current code rather than additional implementation work on those helpers.
- 2026-04-23: prefer the repo harness commands plus App Store Connect prep scripts over manual App Store Connect web edits wherever the existing automation already covers metadata, screenshot sets, and build attachment.
- 2026-04-23: bump the shared project build number to `3` before retrying uploads, because App Store Connect rejected build number `2` as a duplicate and the same project version feeds both macOS and iOS through `Info.plist`.

## Outcomes & Retrospective

Completed:

- `Calendar Busy Sync/Calendar Busy Sync.xcodeproj/project.pbxproj` now advances the shared `CURRENT_PROJECT_VERSION` from `2` to `3`, which updates the bundle version used by both macOS and iOS exports
- `Calendar Busy Sync/Calendar Busy Sync/App/Platform/macOS/MacMenuBarContent.swift` now leaves `MenuPresentationSnapshot` at internal visibility so the existing `@testable` unit test can compile
- a fresh macOS App Store package built from the current workspace uploaded successfully with delivery/build id `24e4bf9e-9fd9-4641-9200-14c7b759f6bd`
- a fresh iOS App Store package built from the current workspace uploaded successfully with delivery/build id `eca85d99-7e79-40db-8244-6ecabf7761f8`
- `scripts/prepare-appstore-macos-submission.py` reattached macOS build `1.0 (3)` and refreshed the existing `APP_DESKTOP` screenshot set
- `scripts/prepare-appstore-ios-submission.py` reattached iOS build `1.0 (3)` and refreshed the existing `APP_IPHONE_67` plus `APP_IPAD_PRO_3GEN_129` screenshot sets

No known App Store Connect blockers remain for this refresh run. The only unresolved validation issue is the pre-existing hosted macOS XCTest runner stall after build.

## Context and Orientation

Relevant files and interfaces:

- `scripts/archive-appstore`
- `scripts/upload-appstore`
- `scripts/prepare-appstore-macos-submission.py`
- `scripts/prepare-appstore-ios-submission.py`
- `docs/exec-plans/active/2026-04-20-macos-app-store-submission.md`
- `docs/exec-plans/completed/2026-04-20-ios-app-store-submission.md`
- `.agents/DOCUMENTATION.md`

External system context:

- App Store Connect app id: `6762634278`
- bundle id: `com.matthewpaulmoore.Calendar-Busy-Sync`
- team id: `GG34PA8F4A`
- release credentials and signing source of truth come from `.env`

Assumptions:

- the local machine still has the Apple account, provisioning state, distribution certificate, installer certificate, and App Store Connect API key required by the scripted upload flow
- the current checked-out code version is the intended source for the refreshed App Store builds once the shared build number is advanced past the previously uploaded App Store build
- existing screenshot assets remain acceptable unless the prep scripts or remote API report otherwise

## Plan of Work

1. Validate the local release prerequisites that the repo scripts depend on.
2. Produce fresh App Store archives/exports for macOS and iOS from the current workspace.
3. Upload the resulting `.pkg` and `.ipa` packages and wait for App Store Connect processing.
4. Re-run the App Store Connect prep helpers so each platform record attaches the newest valid build and reasserts the automated metadata/screenshot state.
5. Record the exact build numbers, App Store Connect build ids, and any remaining blockers.

## Concrete Steps

1. Run `./scripts/bootstrap-apple` to confirm the local Xcode, `.env`, signing, and App Store Connect prerequisites still resolve.
2. If App Store Connect rejects the upload because the build number already exists, bump `CURRENT_PROJECT_VERSION` in `Calendar Busy Sync/Calendar Busy Sync.xcodeproj/project.pbxproj` once and rebuild both platforms from that updated build number.
3. Run:
   - `./scripts/archive-appstore --platform macos`
   - `./scripts/upload-appstore --platform macos --skip-build --wait`
4. Run:
   - `./scripts/archive-appstore --platform ios`
   - `./scripts/upload-appstore --platform ios --skip-build --wait`
5. Refresh App Store Connect state with:
   - `python3 scripts/prepare-appstore-macos-submission.py --screenshot-dir artifacts/appstore/macos-screenshots`
   - `python3 scripts/prepare-appstore-ios-submission.py --iphone-dir artifacts/appstore/ios-screenshots/iphone --ipad-dir artifacts/appstore/ios-screenshots/ipad`
6. If a platform blocks on missing screenshots or credentials, capture the exact failure and stop short of any ad hoc manual workaround that is not already represented in repo automation.

## Validation and Acceptance

Run from repo root:

```bash
python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-22-dual-platform-appstore-refresh.md
./scripts/bootstrap-apple
./scripts/archive-appstore --platform macos
./scripts/upload-appstore --platform macos --skip-build --wait
./scripts/archive-appstore --platform ios
./scripts/upload-appstore --platform ios --skip-build --wait
python3 scripts/prepare-appstore-macos-submission.py --screenshot-dir artifacts/appstore/macos-screenshots
python3 scripts/prepare-appstore-ios-submission.py --iphone-dir artifacts/appstore/ios-screenshots/iphone --ipad-dir artifacts/appstore/ios-screenshots/ipad
```

Acceptance means:

- App Store Connect receives a fresh macOS package and a fresh iOS package built from the current workspace
- each platform record attaches the newest valid build whose short version matches the current App Store version
- automated screenshots and metadata remain populated after the refresh run
- any remaining manual-only blockers are captured explicitly in this plan and the final handoff

## Idempotence and Recovery

- rerunning the archive commands should create new timestamped exports without mutating older release artifacts
- rerunning the upload commands should upload the newest verified package unless an explicit `--package` path is supplied
- rerunning the submission prep helpers should replace screenshot attachments in-place and reattach the latest valid build when possible
- if App Store Connect processing lags, rerun only the prep helper after the uploaded build reaches `VALID` instead of rebuilding immediately

## Artifacts and Notes

- release outputs land under `artifacts/archives/` and `artifacts/exports/`
- screenshot assets are expected under `artifacts/appstore/macos-screenshots/` and `artifacts/appstore/ios-screenshots/`
- keep App Store Connect API credentials, Apple team values, and signing certificate identifiers in `.env` and local keychains only

## Interfaces and Dependencies

- depends on `xcodebuild` for archive/export
- depends on `xcrun altool` for package upload
- depends on `.env` values consumed by `scripts/lib/xcode-env.sh`
- depends on App Store Connect API access from `scripts/prepare-appstore-macos-submission.py`
- depends on App Store Connect API access from `scripts/prepare-appstore-ios-submission.py`
