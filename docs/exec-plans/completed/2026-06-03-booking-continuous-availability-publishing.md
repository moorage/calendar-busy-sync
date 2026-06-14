# Booking Continuous Availability Publishing

## Purpose / Big Picture

Calendar Busy Sync already has a macOS polling loop that periodically runs calendar reconciliation. Booking availability should use that same loop to keep the static GitHub Pages booking site fresh when the user has configured GitHub publishing. The public page remains static and privacy-first, but the native app should regenerate availability from the local calendar, compare the generated artifacts with the last local/remote state, and publish only when the generated public availability changed.

The goal is not to make GitHub Pages a source of truth. The native app remains the authority for live availability and still rechecks requests before approval. The goal is to reduce stale public slot displays, make local-vs-GitHub availability drift easy to understand, and tolerate multiple app installs or agents writing generated booking artifacts without turning that drift into a hard failure.

## Progress

- [x] 2026-06-03T20:59Z Created this ExecPlan after inspecting the existing macOS polling loop, booking generation/publishing flow, GitHub contents publisher, and completed booking UX/IA plan.
- [x] 2026-06-03T21:15Z Added diff-aware GitHub publishing results, remote byte comparison, unchanged-file skips, overwrite warnings, and focused publisher planning tests.
- [x] 2026-06-03T21:20Z Reused `syncNowIfReady()` so macOS polling and iOS best-effort refresh can publish booking availability when GitHub settings and active appointment types exist.
- [x] 2026-06-03T21:25Z Added dashboard/audit evidence for background publish summaries and remote generated-file drift warnings.
- [x] 2026-06-03T21:30Z Updated product, architecture, and implementation notes with the continuous publishing contract and validation evidence.

## Surprises & Discoveries

- The app already has the right background cadence on macOS: `restartSyncLoopIfNeeded()` sleeps for `pollIntervalMinutes` and calls `syncNowIfReady()`. Booking publishing should compose with that pass rather than adding another timer.
- The current GitHub publisher uploads every generated file and treats remote state mostly as a SHA lookup. It does not yet return skipped/uploaded/conflict evidence or compare remote file content before uploading.
- The current booking snapshot can show generated/uploaded/live states, but it does not yet expose a background publishing status or a warning that remote generated availability was changed by another writer.

## Decision Log

- Reuse the existing macOS polling loop and iOS background refresh entry point where possible. Do not add another scheduler.
- Compare generated public artifacts before upload. If local generated content matches the remote file content, skip that file and avoid a commit.
- Treat remote generated-file drift as a warning, not a hard fail. The app may overwrite generated booking artifacts, but it must record that remote content differed before overwrite so the dashboard can explain what happened.
- Keep the diff privacy-safe: compare public generated artifacts only and show counts/paths/fingerprints, not full slot payloads or token contents.

## Outcomes & Retrospective

Implemented. Booking availability publishing now composes with the existing sync cadence instead of adding a new scheduler. The macOS polling loop and iOS best-effort refresh hook call the same guarded publish path after sync; the path quietly skips when GitHub publishing is not configured or no active appointment types exist.

The GitHub publisher now fetches existing Contents API SHA plus base64 file content, skips byte-identical public artifacts, uploads only missing or changed files, and returns uploaded/skipped/overwritten counts. Remote generated-file drift is recorded as a warning and then overwritten with the local source of truth, so multiple writers do not create a hard conflict.

Validation passed:

- `python3 scripts/check_execplan.py docs/exec-plans/active/2026-06-03-booking-continuous-availability-publishing.md`
- `xcrun swiftc -typecheck 'Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/'*.swift`
- `xcodebuild -quiet -project 'Calendar Busy Sync/Calendar Busy Sync.xcodeproj' -scheme 'Calendar Busy Sync' -configuration Debug -derivedDataPath artifacts/DerivedData-booking-continuous-publish -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -only-testing:'Calendar Busy SyncTests/BookingTests' test`
- `./scripts/test-booking-site`
- `./scripts/test-booking-relay-cloudflare`
- `./scripts/test-booking-relay-vercel`
- `./scripts/build --platform macos`

## Context and Orientation

Relevant files:

- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift` owns the polling loop, booking draft generation, GitHub publish action, booking setup snapshot, and audit trail.
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/BookingGitHubPublisher.swift` owns GitHub repository parsing and Contents API uploads.
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/BookingStaticSiteGenerator.swift` generates `public/site-config.json` and `public/availability/slots.json`.
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/BookingSetupState.swift` carries booking page/inbox status labels.
- `Calendar Busy Sync/Calendar Busy Sync/ContentView.swift` renders the Booking workspace Overview and Publish evidence.
- `Calendar Busy Sync/Calendar Busy SyncTests/BookingTests.swift` is the focused booking test target.
- `docs/product-specs/privacy-first-booking.md` documents booking freshness, publishing, and remote drift behavior.
- `.agents/DOCUMENTATION.md` records durable implementation evidence.

Assumptions:

- Continuous publishing is macOS-first because macOS has a reliable app-owned timer. iOS can opportunistically run the same refresh hook during background refresh, but the app must not promise fixed iOS cadence.
- A configured GitHub token and repository means the user has opted into app-managed GitHub Pages publishing.
- Overwriting generated public files is acceptable when another app instance changed them; warning is required, blocking is not.
- Request approval remains protected by local live availability recheck even if the public page lags.

## Plan of Work

1. Add a small publish-result model for generated booking artifacts.
   - Return uploaded/skipped/overwritten counts and warning paths from `BookingGitHubPublisher`.
   - Fetch existing GitHub contents with SHA and base64 content so unchanged files can be skipped.
   - Keep commit messages stable and avoid commits for byte-identical files.

2. Add app-level background booking publishing.
   - Track whether a background booking publish is in flight to avoid overlapping timer/manual uploads.
   - Add a `publishBookingAvailabilityIfNeeded(reason:)` path that regenerates page files, compares the generated fingerprint with the last uploaded fingerprint, and uploads only when needed.
   - Call it after the existing sync pass on macOS polling and from the iOS background refresh handler as best-effort work.
   - Skip quietly when booking is not configured for GitHub publishing or no active appointment types exist.

3. Surface status and warnings.
   - Persist and expose a compact background publish summary.
   - Show last background publish status in the Booking Overview/Publish evidence.
   - Record remote drift as a warning audit entry and dashboard message, not as a failed publish.

4. Update tests and docs.
   - Add focused unit tests for publisher no-change skipping, remote drift warning/overwrite results, and app-level summary copy where practical.
   - Update product docs, `.agents/DOCUMENTATION.md`, and this ExecPlan with validation evidence.

## Concrete Steps

1. Inspect `BookingGitHubPublisher` and add response types for `uploadedCount`, `skippedCount`, `overwrittenCount`, `remoteChangedPaths`, and `changedRelativePaths`.
2. Decode GitHub Contents API `content` for existing files; compare bytes after removing API line wrapping.
3. Change manual `publishBookingPageToGitHub()` to use the richer result and clearer status messages.
4. Add `bookingAvailabilityPublishSummary` state in `AppModel`, plus a persisted last background status string if low-cost.
5. Add guarded `publishBookingAvailabilityIfNeeded(reason:)` and call it from `syncNowIfReady()` after busy sync and from `handleIOSBackgroundRefreshTask()` after `syncNowIfReady()`.
6. Add Booking workspace evidence lines for background publishing and remote drift warnings.
7. Add focused tests for the pure publisher planning/result behavior without hitting GitHub.
8. Run validation and update docs.

## Validation and Acceptance

Acceptance criteria:

- The macOS polling loop attempts booking availability publishing after calendar sync when GitHub repository/token/page configuration exists.
- If regenerated public availability matches the last uploaded/generated fingerprint or remote bytes, no GitHub commit is made.
- If remote generated booking artifacts differ from local generated output, the app overwrites them but records a visible warning/audit entry with paths/counts.
- Manual publishing still works and uses the same diff/skip/warning behavior.
- No public diff or warning exposes provider credentials, calendar IDs, raw busy intervals, private keys, admin tokens, visitor plaintext, or GitHub tokens.

Validation commands:

- `python3 scripts/check_execplan.py docs/exec-plans/active/2026-06-03-booking-continuous-availability-publishing.md`
- `xcrun swiftc -typecheck 'Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/'*.swift`
- `./scripts/test-booking-site`
- `./scripts/test-booking-relay-cloudflare`
- `./scripts/test-booking-relay-vercel`
- `xcodebuild -project 'Calendar Busy Sync/Calendar Busy Sync.xcodeproj' -scheme 'Calendar Busy Sync' -configuration Debug -derivedDataPath artifacts/DerivedData-booking-continuous-publish -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -only-testing:'Calendar Busy SyncTests/BookingTests' test`
- `./scripts/build --platform macos`
- `python3 scripts/knowledge/check_docs.py`
- `git diff --check`

## Idempotence and Recovery

Repeated background passes with unchanged local availability should skip GitHub writes. If the remote generated files differ, the app overwrites generated booking artifacts with the current local source of truth and records a warning that another writer changed them first. If GitHub upload fails because of auth, network, repository, or API issues, keep the previous public page state and record a failed publish message without deleting local generated files.

Rollback is additive: remove the background publish call sites and the richer publisher result plumbing; manual page generation, manual GitHub upload, and request approval remain intact.

## Artifacts and Notes

- Prior completed UX/IA plan: `docs/exec-plans/completed/2026-06-03-booking-ux-ia-refresh.md`.
- Existing booking implementation plan: `docs/exec-plans/active/2026-05-31-privacy-first-booking-pages-relay.md`.
- No generated artifacts should be checked in. Browser screenshots and local generated sites remain under `artifacts/`.

## Interfaces and Dependencies

- GitHub Contents API remains the publishing API.
- Booking public artifacts remain `public/site-config.json`, `public/availability/slots.json`, template assets, and static files under the configured folder.
- Booking secrets remain in `BookingSecretStore`; tokens are never written to docs, generated public files, screenshots, or audit entries.
- macOS timer behavior remains governed by `pollIntervalMinutes`; iOS background behavior remains best-effort and OS-controlled.
