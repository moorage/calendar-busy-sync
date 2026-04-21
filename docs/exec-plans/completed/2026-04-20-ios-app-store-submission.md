# iOS App Store Submission Pass

## Purpose / Big Picture

Package the current iPhone/iPad app for App Store submission, upload and attach a valid `1.0` iOS build, and populate the missing iOS App Store Connect record so the universal app is ready for review on both Apple storefronts. This pass needs an iOS-specific screenshot capture path, iOS metadata/review-detail automation, and a verified upload/attach flow that matches the existing macOS release harness.

## Progress

- [x] 2026-04-20T23:40Z inspect the iOS App Store Connect record and confirm the current gaps: no attached build, no screenshots, no review detail, and missing support/marketing URLs
- [x] 2026-04-20T23:50Z add deterministic iOS App Store screenshot capture for the required iPhone and iPad display classes
- [x] 2026-04-21T00:00Z add iOS App Store Connect preparation automation for screenshots, metadata, and review detail
- [x] 2026-04-21T00:10Z archive/upload a fresh `1.0` iOS build and attach it to the App Store Connect iOS version

## Surprises & Discoveries

- 2026-04-20: the iOS App Store Connect version exists at `1.0`, but App Store Connect currently has no attached build, no review-detail record, and no screenshot sets for that platform
- 2026-04-20: the existing uploaded iOS builds are still under pre-release version `0.1`, so the iOS App Store pass needs a fresh upload from the current `1.0` project version before the record can be attached
- 2026-04-20: App Store Connect’s API still uses screenshot display enums like `APP_IPHONE_67` and `APP_IPAD_PRO_3GEN_129`; using an iPhone 16 Pro Max would produce 6.9-inch screenshots that do not match the upload set Apple currently accepts through the API
- 2026-04-20: `scripts/upload-appstore --platform ios` still archives by default even when an explicit `--package` is supplied; that is safe, but slower than necessary for a pure upload retry

## Decision Log

- 2026-04-20: create a separate iOS submission ExecPlan instead of overloading the macOS plan, because the iOS pass needs different screenshot capture, metadata completeness checks, and build attachment state
- 2026-04-20: target the highest-coverage screenshot sets Apple currently accepts for a universal iPhone/iPad app through the API: `APP_IPHONE_67` and `APP_IPAD_PRO_3GEN_129`
- 2026-04-20: reuse the app’s existing screenshot-mode UI (`--app-store-screenshot`) and capture the final image from booted simulators with `xcrun simctl io screenshot` instead of introducing a second iOS-only in-app image renderer

## Outcomes & Retrospective

Completed:

- the repo now has deterministic iOS App Store screenshot generation via `./scripts/capture-appstore-screenshots-ios`
- the screenshot path captures 3 iPhone `1290x2796` assets and 3 iPad `2048x2732` assets from booted simulators using the app’s existing screenshot-mode UI
- the repo now has `scripts/prepare-appstore-ios-submission.py`, which attaches the latest valid `1.0` iOS build, fills in support/marketing URLs plus review detail, and uploads both required screenshot sets for app `6762634278`
- App Store Connect now shows:
  - iOS app-store version `1.0`
  - attached iOS build `1.0 (2)` with build id `bc83e9b0-2414-4c24-95cc-32f276317003`
  - review contact `Matthew Moore`, `matt@souschefstudio.com`, `650-888-5962`
  - support URL `https://souschefstudio.com/`
  - marketing URL `https://souschefstudio.com/`
  - one `APP_IPHONE_67` screenshot set with 3 uploaded screenshots
  - one `APP_IPAD_PRO_3GEN_129` screenshot set with 3 uploaded screenshots

Still blocked:

- no known automation blockers remain for the iOS submission record; optional copy fields like `whatsNew` and `promotionalText` are still unset

## Context and Orientation

Relevant files and interfaces:

- `scripts/archive-appstore`
- `scripts/upload-appstore`
- `scripts/lib/xcode-env.sh`
- `scripts/build`
- `scripts/capture-checkpoint`
- `Calendar Busy Sync/Calendar Busy Sync/Calendar_Busy_SyncApp.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Support/AppStoreScreenshotView.swift`
- `Calendar Busy Sync/Calendar Busy Sync/Harness/HarnessLaunchOptions.swift`
- `docs/harness.md`
- `.agents/DOCUMENTATION.md`

External system context:

- App Store Connect app id: `6762634278`
- iOS app-store version id: `916bda49-8726-4888-b550-02d81db0909e`
- bundle id: `com.matthewpaulmoore.Calendar-Busy-Sync`
- team id: `GG34PA8F4A`
- App Store Connect API credentials come from `.env`

Assumptions:

- the current iOS archive/export path can still produce a valid `.ipa` signed for App Store distribution under the configured team
- the same review-contact values used for macOS can be reused for iOS
- simulator-based screenshots are acceptable as long as they match App Store Connect’s required display classes and asset dimensions

## Plan of Work

1. Add a deterministic iOS screenshot capture script that launches the app into its screenshot-mode UI on a booted iPhone and iPad simulator, captures the screen PNGs into `artifacts/appstore/ios-screenshots/`, and is safe to rerun.
2. Add an iOS App Store Connect preparation helper that:
   - finds the iOS `1.0` version
   - attaches the latest valid `1.0` build
   - sets support and marketing URLs
   - creates/refreshes the required iPhone and iPad screenshot sets
   - uploads screenshots
   - creates or updates the review-detail record from `.env`
3. Upload a fresh iOS `1.0` build from the current repo state and confirm that App Store Connect marks it `VALID`.
4. Re-query the iOS App Store Connect record and document any remaining manual-only fields.

## Concrete Steps

1. Extend `scripts/lib/xcode-env.sh` with preferred simulator helpers for App Store iPhone/iPad screenshot devices.
2. Add `scripts/capture-appstore-screenshots-ios` that:
   - builds the app for the correct simulator destinations
   - boots the chosen iPhone and iPad simulators
   - launches the app with `--app-store-screenshot overview|mirrors|logs`
   - captures deterministic PNGs with `xcrun simctl io screenshot`
   - stores them under:
     - `artifacts/appstore/ios-screenshots/iphone/`
     - `artifacts/appstore/ios-screenshots/ipad/`
3. Add `scripts/prepare-appstore-ios-submission.py` that:
   - finds the iOS `1.0` app-store version
   - attaches the latest valid `1.0` iOS build
   - sets support URL, marketing URL, and review detail
   - creates and refreshes screenshot sets for:
   - `APP_IPHONE_67`
     - `APP_IPAD_PRO_3GEN_129`
   - uploads the generated PNGs
4. Run:
   - `./scripts/archive-appstore --platform ios`
   - `./scripts/upload-appstore --platform ios --skip-build --wait`
   - `python3 scripts/prepare-appstore-ios-submission.py --iphone-dir artifacts/appstore/ios-screenshots/iphone --ipad-dir artifacts/appstore/ios-screenshots/ipad`
5. Update docs and implementation notes so the iOS submission path is discoverable next time.

## Validation and Acceptance

Run from repo root:

```bash
./scripts/capture-appstore-screenshots-ios
./scripts/archive-appstore --platform ios
./scripts/upload-appstore --platform ios --skip-build --wait
python3 scripts/prepare-appstore-ios-submission.py --iphone-dir artifacts/appstore/ios-screenshots/iphone --ipad-dir artifacts/appstore/ios-screenshots/ipad
python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-20-ios-app-store-submission.md
python3 scripts/knowledge/check_docs.py
```

Acceptance means:

- a valid `1.0` iOS build is uploaded and attached to the iOS App Store Connect version
- the iOS record has review contact metadata plus support/marketing/privacy URLs populated
- the required iPhone and iPad screenshot sets exist and all uploaded assets are complete
- any remaining manual-only submission requirements are explicitly documented

## Idempotence and Recovery

- rerunning iOS screenshot capture should overwrite only generated screenshots under `artifacts/appstore/ios-screenshots/`
- rerunning the archive/upload path should create a new timestamped archive/export without mutating old artifacts
- rerunning the iOS prep helper should replace existing screenshots in the targeted sets rather than accumulating duplicates
- if App Store Connect rejects a screenshot set or build attachment, keep the local artifacts and record the exact failing response before retrying

## Artifacts and Notes

- store generated iOS screenshots and exported `.ipa` artifacts under `artifacts/`
- keep review-contact data and App Store Connect credentials in `.env` only

## Interfaces and Dependencies

- depends on `xcodebuild`, `xcrun simctl`, and `xcrun altool`
- depends on the existing App Store Connect API credentials from `.env`
- depends on bootable iPhone and iPad simulators for the targeted screenshot classes
- depends on App Store Connect API support for iOS screenshot set creation and upload
