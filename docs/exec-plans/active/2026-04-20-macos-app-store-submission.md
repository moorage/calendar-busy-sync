# macOS App Store Submission Pass

## Purpose / Big Picture

Package the current macOS app for App Store submission, upload the newest build, and make the App Store Connect macOS record materially ready for review by filling in the missing submission-facing assets and metadata that can be automated from this repo. That includes a validated archive/upload path, a reproducible screenshot capture path, and an explicit record of what still must be provided manually if Apple or the current tooling blocks a field.

## Progress

- [x] 2026-04-20T22:05Z create a dedicated release ExecPlan for the macOS submission pass so build/upload, screenshots, and App Store Connect state live in one place
- [x] 2026-04-20T22:10Z inspect the current App Store Connect app/version state for the macOS app record and identify missing submission prerequisites
- [x] 2026-04-20T22:20Z add missing repo automation for release screenshots and App Store Connect metadata updates
- [x] 2026-04-20T22:35Z archive and upload a fresh macOS App Store package built from the current `main` commit
- [x] 2026-04-21T00:55Z attach the valid `1.0 (2)` macOS build to the App Store Connect submission record after fixing the stale-upload and false-error harness bugs
- [x] 2026-04-20T22:45Z populate the macOS submission assets and metadata that the current API and credentials can edit, then record remaining manual-only steps
- [x] 2026-07-07T07:12Z archive/export the current macOS app successfully, then verify the upload now reaches App Store Connect's agreement gate when the app id is passed explicitly
- [x] 2026-07-07T16:54Z verify the DSA compliance requirement is active and capture the next upload blocker: App Store Connect rejects duplicate build number `6`
- [x] 2026-07-07T17:00Z bump the shared project build number to `7` for the next macOS App Store upload attempt
- [x] 2026-07-07T17:57Z capture App Store server validation failures for build `1.3 (7)`: closed train, helper sandbox/signing identifiers, and `arm64e` helper slices
- [x] 2026-07-07T18:05Z bump marketing version to `1.4` and re-sign/thin bundled Git/SSH helpers for App Store validation
- [x] 2026-07-07T18:03Z capture App Store server validation failure for build `1.4 (7)`: copied Git's embedded Mach-O plist lacked `CFBundleIdentifier`
- [x] 2026-07-07T18:08Z patch copied helpers' embedded Mach-O plist sections to app-owned `CFBundleIdentifier` values before signing
- [x] 2026-07-07T17:10Z upload and process macOS build `1.4 (7)` successfully; App Store Connect marked delivery `c278abd8-20fb-46df-babf-9fe0bd455571` as `VALID`
- [x] 2026-07-07T17:14Z create macOS App Store version `1.4`, attach build `1.4 (7)`, and refresh the automated macOS screenshot set
- [x] 2026-07-07T17:16Z remove availability from the 27 EU App Store territories at the user's direction, leaving 148 non-EU territories available
- [x] 2026-07-07T17:16Z submit macOS version `1.4` for App Review; review submission `c1e1c8c5-e591-4b63-ba64-fd3ec419a3e0` is `WAITING_FOR_REVIEW`
- [x] 2026-07-07T19:07Z capture automated App Review blocker for build `1.4 (7)`: the binary uses or references non-public or deprecated APIs
- [x] 2026-07-07T19:15Z remove copied Git/SSH helper binaries from archive/install builds and bump the replacement App Store build number to `8`

## Surprises & Discoveries

- 2026-04-20: the initial screenshot pipeline appeared to succeed while writing nothing because the signed macOS app is sandboxed and could not write PNGs back into the repo `artifacts/` directory; the release capture path needed to use an unsigned app build plus explicit output-file verification
- 2026-04-20: App Store Connect's current age-rating payload mixes booleans and enum strings; the prep helper had to send `false` for fields like `advertising` and `userGeneratedContent`, while still using `"NONE"` for actual content-rating dimensions
- 2026-04-20: App Store Connect accepted metadata and screenshots without a matching build, so the submission-prep helper was changed to keep going and report the missing-build condition instead of failing before screenshots upload
- 2026-04-20: the local Apple-account state initially lacked a `Mac Installer Distribution` certificate; creating and importing one through App Store Connect unblocked `xcodebuild -exportArchive`
- 2026-04-20: `scripts/upload-appstore` originally chose the alphabetically last exported package, which accidentally uploaded a stale `auto-macos-test` build instead of the newest App Store export; the selector now uses modification time
- 2026-04-20: App Store Connect returns `204 No Content` for a successful build-attachment PATCH, so the submission helper must treat both `200` and `204` as success
- 2026-07-07: `altool --upload-package` can fail to infer the app record from `com.matthewpaulmoore.Calendar-Busy-Sync` on macOS; passing App Store Connect app id `6762634278` gets past that lookup and exposes the current account blocker.
- 2026-07-07: after DSA compliance became active, App Store Connect accepted the upload request far enough to reject the package as duplicate bundle version `6`; the next archive needs `CURRENT_PROJECT_VERSION = 7`.
- 2026-07-07: App Store Connect now rejects additional copied-helper details that local export did not catch: copied Apple SSH helpers keep reserved `com.apple.*` signing identifiers unless re-signed with explicit app-owned identifiers, all embedded executables need sandbox entitlements, and `arm64e` helper slices are invalid unless paired with `arm64`.
- 2026-07-07: version `1.3` is closed for new macOS build uploads, so the next upload must use `CFBundleShortVersionString` `1.4`.
- 2026-07-07: CodeDirectory identifiers are not enough for copied command-line tools. App Store Connect also reads the Mach-O `__TEXT,__info_plist` section, so copied helpers need that embedded plist patched before signing.
- 2026-07-07: App Store Connect's `appAvailabilities` resource is not patchable. Existing EU territory removals have to use per-territory `PATCH /v1/territoryAvailabilities/{id}` updates; the account still reports `availableInNewTerritories = true`, which may require App Store Connect UI if future storefront policy needs to be disabled globally.
- 2026-07-07: App Review's non-public/deprecated API blocker appeared only after the build started shipping copied Apple Git/SSH command-line tools. The submitted app binary did not add comparable linked libraries, while `booking-ssh` and `booking-ssh-keygen` linked system libraries such as `libEndpointSecuritySystem.dylib` and carried `csops` strings. App Store archives should not bundle those copied tools.

## Decision Log

- 2026-04-20: create one release-specific ExecPlan instead of overloading the signing-source-of-truth plan, because this pass also includes screenshots, version metadata, and submission-state checks
- 2026-04-20: generate App Store screenshots from an unsigned macOS build instead of the signed debug app, because the signed sandboxed app cannot write rendered PNGs into repo-local artifact paths
- 2026-04-20: let the App Store submission prep helper continue when no matching macOS build exists so metadata, category, age rating, and screenshots can still be applied before the final upload blocker is removed
- 2026-04-20: prefer newest-by-modification-time export discovery over lexicographic path ordering in `scripts/upload-appstore`, because repo-local helper exports like `auto-macos-test` can sort after timestamped App Store exports while still being stale
- 2026-07-07: have `scripts/upload-appstore` pass the known App Store Connect app id to `altool`, while still allowing `--app-id` or `APPSTORE_CONNECT_APP_ID` overrides.
- 2026-07-07: advance the shared Xcode build number from `6` to `7` before rebuilding, matching App Store Connect's requirement that the next `CFBundleVersion` be higher than the previous macOS upload.
- 2026-07-07: advance the shared marketing version from `1.3` to `1.4`, prefer the Command Line Tools universal Git binary when available, strip `arm64e` slices from bundled helpers, and sign helpers with app-owned identifiers plus sandbox/network entitlements.
- 2026-07-07: rewrite copied helpers' embedded Mach-O plist sections in-place with app-owned `CFBundleIdentifier` values before re-signing, because the original Apple tool plists either lack that key or use reserved `com.apple.*` identifiers.
- 2026-07-07: create the new macOS App Store version through the App Store Connect API instead of Safari, because the repo prep helper can attach builds and screenshots once the editable `1.4` version exists.
- 2026-07-07: remove current EU storefront availability before App Review submission, matching the user's direction not to distribute in the EU while leaving non-EU storefront availability intact.
- 2026-07-07: omit copied Booking Git/SSH helpers from archive/install builds by default and rely on the existing missing-helper error path for App Store builds until the publishing path has a review-safe in-process implementation.

## Outcomes & Retrospective

Completed:

- the repo now has deterministic macOS App Store screenshot generation via `./scripts/capture-appstore-screenshots-macos`
- the app has dedicated App Store screenshot launch flags and renders `overview`, `mirrors`, and `logs` shots directly to 2880x1800 PNGs
- the repo now has `scripts/prepare-appstore-macos-submission.py`, which uploaded the macOS screenshot set and populated App Store Connect metadata for app `6762634278`
- the repo now has a fully working macOS App Store archive/upload path again, including local installer-certificate creation/import, correct newest-export selection in `scripts/upload-appstore`, and successful upload of macOS build `1.0 (2)`
- macOS build `1.4 (7)` uploaded successfully from the current `main` line, processed as `VALID`, and is attached to App Store Connect macOS version `1.4`
- App Store availability now has the 27 EU territories marked unavailable and processing toward not-available; 148 non-EU territories remain available
- macOS version `1.4` is submitted for App Review and review submission `c1e1c8c5-e591-4b63-ba64-fd3ec419a3e0` is in `WAITING_FOR_REVIEW`
- after App Review flagged build `1.4 (7)` for non-public/deprecated API references, archive/install builds now remove `booking-git`, `booking-ssh`, `booking-ssh-keygen`, and `booking-git-core` before packaging; the replacement upload uses build number `8`
- App Store Connect now shows:
  - primary category `PRODUCTIVITY`
  - macOS age rating `4+`
  - support URL `https://souschefstudio.com/`
  - marketing URL `https://souschefstudio.com/`
  - privacy policy URL `https://souschefstudio.com/privacy`
  - one `APP_DESKTOP` screenshot set with 4 uploaded screenshots
  - attached macOS build `1.4 (7)` with build id `c278abd8-20fb-46df-babf-9fe0bd455571`

Follow-up:

- App Store Connect still reports `availableInNewTerritories = true`. Existing EU countries are removed, but if Apple adds future EU storefronts, disable automatic new-territory availability in the web UI or through a confirmed newer API path.

## Context and Orientation

Relevant files and interfaces:

- `scripts/archive-appstore`
- `scripts/upload-appstore`
- `scripts/lib/xcode-env.sh`
- `Calendar Busy Sync/Calendar Busy Sync/Assets.xcassets/AppIcon.appiconset`
- `README.md`
- `.agents/DOCUMENTATION.md`
- `docs/exec-plans/active/2026-04-20-signing-identity-source-of-truth.md`

External system context:

- App Store Connect app id: `6762634278`
- bundle id: `com.matthewpaulmoore.Calendar-Busy-Sync`
- team id: `GG34PA8F4A`
- App Store Connect API credentials come from `.env`

Assumptions:

- the current local Apple account state can still produce a valid macOS archive for the configured team
- the app icon embedded in the archive should come from the Xcode asset catalog and not require a separate manual upload path
- screenshots may require new local automation because the repo currently only carries harness checkpoint images, not App Store-sized submission captures

## Plan of Work

1. Inspect the current App Store Connect macOS version state and determine exactly which editable fields, screenshot sets, and submission prerequisites are still missing.
2. Add or adapt local automation for App Store screenshot generation so the release flow is reproducible from the repo.
3. Build and upload a fresh macOS package with the existing archive/upload harness.
4. Update the editable App Store Connect metadata and screenshots, then record any manual-only fields or blockers.

## Concrete Steps

1. Query App Store Connect for app `6762634278` and the current macOS app-store version, including:
   - version string
   - build linkage
   - editable localization fields
   - screenshot sets / screenshot state
   - submission completeness blockers if the API exposes them
2. If screenshot automation is missing, add a repo script that:
   - launches the macOS app in a deterministic state
   - captures App Store-sized screenshots into `artifacts/`
   - can be rerun without editing source files
3. Run:
   - `./scripts/archive-appstore --platform macos`
   - `./scripts/upload-appstore --platform macos --skip-build`
4. Update App Store Connect metadata for the macOS app version with the API credentials from `.env`, including:
   - description
   - keywords
   - support URL
   - marketing URL or privacy policy URL if available locally
   - screenshots for the macOS localization being submitted
5. Document the exact submission state, including any fields Apple still requires through the web UI or any missing user-provided URLs/text.

## Validation and Acceptance

Run from repo root:

```bash
python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-20-macos-app-store-submission.md
./scripts/archive-appstore --platform macos
./scripts/upload-appstore --platform macos --skip-build
python3 scripts/knowledge/check_docs.py
```

Acceptance means:

- a fresh macOS App Store package is archived and uploaded from the current repo state, and the matching `1.0` build is attached to the App Store Connect macOS version
- the macOS App Store Connect record has the best-available metadata and screenshots populated from automation
- any remaining manual-only submission requirements are explicitly documented, not left implicit

## Idempotence and Recovery

- rerunning screenshot capture should overwrite or replace only generated release artifacts under `artifacts/`
- rerunning the archive/upload path should create a new timestamped archive/export without mutating old exports
- if App Store Connect rejects an upload or screenshot asset, keep the generated local artifacts and record the failing API response in this plan so the next run can resume from the same state
- if metadata updates partially apply, re-query the remote state before attempting another patch so the next request is based on reality

## Artifacts and Notes

- store generated screenshots, exported packages, and any App Store submission helper output under `artifacts/`
- keep secret material in `.env` and existing local key files only; do not copy them into repo docs or generated artifacts

## Interfaces and Dependencies

- depends on `xcodebuild`, `xcrun altool`, and the existing archive/upload scripts
- depends on App Store Connect API credentials from `.env`
- depends on an unsigned macOS app build being launchable for screenshot capture
- depends on App Store Connect API support for the targeted metadata and screenshot endpoints
- depends on a local review-contact phone number before the App Store review-detail record can be fully automated
