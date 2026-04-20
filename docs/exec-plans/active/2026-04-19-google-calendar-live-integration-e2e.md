# Google Calendar Live Integration And E2E

## Purpose / Big Picture

Extend the existing Google Sign-In wiring into a real live Google Calendar integration that can:

- restore or establish multiple Google sessions on macOS, iPhone, and iPad
- keep a roster of connected Google accounts instead of a single mutable slot
- enumerate writable calendars for each connected Google account
- let the user select which calendar in each account should receive writes
- create and delete a managed busy-slot event in the selected calendar for any connected account
- drive a real macOS end-to-end smoke flow against the test account declared in `.env`

This slice still does not implement the full cross-account mirroring engine, but it now needs to satisfy the actual product shape: one user can keep several Google accounts connected at once, manage them from an intuitive settings surface, and prove write access on each selected destination calendar.

## Progress

- [x] 2026-04-19T01:20Z inspect the live-auth implementation and existing harness/test surfaces for the first provider-backed write slice
- [x] 2026-04-19T01:33Z add a Google Calendar provider layer for calendar list, event insert, and event delete using the signed-in user's refreshed access token
- [x] 2026-04-19T01:39Z patch the app model and settings UI so live calendar selection and managed event actions work alongside the scenario-backed shell
- [x] 2026-04-19T01:43Z add coverage for calendar decoding, selection persistence, and CRUD state transitions
- [x] 2026-04-19T01:52Z build a repeatable macOS end-to-end smoke runner that uses `TEST_GOOGLE_USER`, `TEST_GOOGLE_USER_PASSWORD`, and `TEST_GOOGLE_CALENDAR_NAME`
- [x] 2026-04-19T22:15Z guard macOS Google auth from unsigned local harness launches and surface signed-build guidance instead of letting the flow fail later with a generic keychain error
- [x] 2026-04-19T22:40Z inspect the existing single-account implementation, confirm `GIDSignIn` only maintains one `currentUser`, and revise the workstream around a persisted multi-account roster plus a clearer account-management UI
- [x] 2026-04-19T23:05Z ship the secure multi-account Google roster, per-account calendar selection, and roster-based settings UI with primary-account affordances
- [x] 2026-04-19T01:55Z run build/test/docs verification, complete the live-auth round trip, and reconcile the documentation log

## Surprises & Discoveries

- 2026-04-19: the GoogleSignIn package already present in `DerivedData` exposes `GIDGoogleUser.accessToken.tokenString` and refresh helpers, so the app can call the Calendar REST API directly without adding a second Google API client library.
- 2026-04-19: the Xcode target already has `DEVELOPMENT_TEAM = GG34PA8F4A`, `CODE_SIGN_STYLE = Automatic`, and `CODE_SIGN_IDENTITY = Apple Development`, which means live macOS auth can be exercised with a signed debug build instead of the no-signing harness build.
- 2026-04-19: the current app still assumes a scenario fixture is always present at launch, so a live-provider workflow needs a safe empty-shell fallback instead of throwing a startup error when no scenario arguments are supplied.
- 2026-04-19: the no-signing harness build is sufficient for Google Calendar REST calls after authentication, but it is not sufficient evidence for the macOS auth handoff itself because the Google browser/session flow stalls before completion on this machine.
- 2026-04-19: `open -n ... --args` does not propagate environment variables into the app process, so the live smoke runner has to use `launchctl setenv` before launching the app.
- 2026-04-19: the first version of the live smoke script was too optimistic about UI readiness and exited before the Connect button appeared; the runner now waits for the control or relies on debug-only auto-sign-in.
- 2026-04-19: `scripts/lib/ax-query.swift` initially failed to compile under Swift 6 because of invalid `AXValue` downcasts, which made the live smoke script silently miss visible controls until the helper was fixed.
- 2026-04-19: the system auth logs are explicit now: `SafariLaunchAgent` starts the Google session and then records `User cancelled request with flags: 3` plus `Could not activate app with pid ...`, which is the concrete blocker for this machine's live macOS run.
- 2026-04-19: the manual app launch I opened from `artifacts/DerivedData` was also an unsigned harness build, which reproduces as a post-OAuth keychain failure even when the browser round trip itself succeeds.
- 2026-04-19: the linked GoogleSignIn package only exposes a single `currentUser`, and its public contract says an interactive sign-in replaces saved sign-in state, so true multi-account support must add an app-owned account roster instead of reusing one mutable slot.
- 2026-04-19: `GIDGoogleUser` is `NSSecureCoding` and its `refreshTokensIfNeeded` path operates on the instance auth state rather than requiring `GIDSignIn.sharedInstance.currentUser`, which makes a keychain-backed stored-account roster viable.
- 2026-04-19: the roster UI became much clearer once it exposed per-account cards with one destination-calendar picker, a "Make Primary" action, and compact overview counts instead of treating Google as one shared reconnect flow.
- 2026-04-19: silently importing `GIDSignIn`'s previous-session cache on launch fights the app-owned roster and can resurrect the wrong Google account even when the secure store is empty; the app needs to treat the roster as the only restore source.
- 2026-04-19: the live smoke harness was timing out before auth because `cliclick` landed on the right screen coordinates but did not reliably fire the SwiftUI button action; an explicit accessibility `AXPress` is stable.
- 2026-04-19: `login_hint` alone was not enough to keep the auth flow on the `.env` test user, but constraining the live run with `hostedDomain` derived from the test email's Workspace domain made the signed macOS end-to-end flow deterministic on this machine.

## Decision Log

- 2026-04-19: keep the existing scenario-backed shell for previews and harness snapshots, but layer live Google account/calendar state on top instead of replacing the scenario model outright.
- 2026-04-19: use direct Calendar REST calls with `URLSession` and the GoogleSignIn access token rather than adding another heavy dependency for one read/write path.
- 2026-04-19: treat writable calendars as the first user-facing selection set, using Google Calendar `minAccessRole=writer` to avoid presenting read-only calendars that cannot accept mirrored busy slots.
- 2026-04-19: support a debug-only macOS live smoke mode that can auto-select the calendar named by the test environment and run create/delete once authentication completes, so end-to-end verification does not depend on brittle post-login UI clicking.
- 2026-04-19: trigger Google sign-in automatically when the app is launched in live smoke mode and no prior session is available, because the E2E harness should not depend on a race-prone initial button click.
- 2026-04-19: keep the live smoke launcher on `open -n` rather than executing the app binary directly so LaunchServices continues to deliver the OAuth callback URL to the correct app instance.
- 2026-04-19: block interactive macOS Google sign-in when the running app is unsigned or missing a team-based signing identity, because that path cannot persist the Google session in the macOS keychain and only produces misleading downstream errors.
- 2026-04-19: implement multiple Google accounts by storing encoded `GIDGoogleUser` sessions in an app-owned secure store and loading one selected account into operational context when listing calendars or writing verification events.
- 2026-04-19: replace the single Google summary section with an account roster UI that emphasizes “Add account”, per-account status, per-account calendar selection, and per-account test actions over a single reconnect button.
- 2026-04-19: stop auto-importing `GIDSignIn` previous-session state on launch and clear SDK session state before interactive sign-in, so stale SDK keychain data cannot override the app-owned multi-account roster.
- 2026-04-19: have the macOS live smoke runner build and launch a signed app, drive buttons via `AXPress`, and set a target account email from `.env`; when that email belongs to a Google Workspace domain, use `hostedDomain` plus a post-sign-in email check to keep the verification loop on the intended account.

## Context and Orientation

Relevant files:

- `.env`
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/GoogleSignInService.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/GoogleAccountStore.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/ScenarioModels.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/ConnectedAccountList.swift`
- `Calendar Busy Sync/Calendar Busy Sync/ContentView.swift`
- `Calendar Busy Sync/Calendar Busy Sync/Harness/AccessibilityIDs.swift`
- `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`
- `Calendar Busy Sync/Calendar Busy SyncUITests/Calendar_Busy_SyncUITests.swift`
- `scripts/build`
- `scripts/test-unit`
- `scripts/test-ui-macos`
- `docs/debug-contracts.md`
- `.agents/DOCUMENTATION.md`

External references that shape this work:

- Google Sign-In API access guidance: `https://developers.google.com/identity/sign-in/ios/api-access`
- Google Calendar events reference: `https://developers.google.com/workspace/calendar/api/v3/reference/events`
- Google Calendar events insert reference: `https://developers.google.com/workspace/calendar/api/v3/reference/events/insert`

## Assumptions

- the product needs simultaneous Google-account connectivity in one app session, not just a quick account switcher
- an account roster may rely on app-owned secure persistence even though `GIDSignIn` itself only restores one saved session
- destination-calendar selection remains one writable calendar per connected Google account for this slice
- verification writes can stay account-local and private; the full cross-account mirror engine still follows later
- local keychain persistence for account snapshots is acceptable on macOS and iOS as long as account data stays out of logs, fixtures, and `UserDefaults`

## Plan of Work

1. Add a secure Google account store and provider helpers that can persist, load, and operate on multiple encoded Google user sessions without relying on one mutable global slot.
2. Expand `AppModel` from one Google account plus one selected calendar into an ordered roster of Google accounts, each with its own writable calendars, selected destination calendar, verification-event state, and activation status.
3. Replace the single Google settings section with a more intuitive account-management UI centered on “Add Google account” plus per-account cards for status, calendar selection, verification actions, and disconnect/remove controls.
4. Update connected-account summaries, audit-trail entries, and accessibility identifiers so the rest of the shell reflects multiple live Google accounts cleanly.
5. Add unit and UI coverage for account persistence, second-account connection, per-account calendar selection, and account-specific verification writes.
6. Re-run signed macOS validation and the live Google flow against a signed build, then update docs and execution notes.

## Concrete Steps

1. Add Google account persistence under `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/`:
   - account snapshot model with stable account IDs
   - secure archive/unarchive of `GIDGoogleUser`
   - keychain-backed storage for multiple account records
   - helpers to save a newly signed-in account, list stored accounts, remove one account, and load one account for operations
2. Patch `GoogleSignInService.swift` and `GoogleCalendarService.swift` so the app can:
   - sign in an additional Google account without discarding the roster
   - refresh calendars and write/delete verification events for a specified stored account
   - keep per-account operational failures scoped to the relevant card instead of one global Google message
3. Patch `AppModel.swift` so the app can:
   - launch without scenario arguments
   - restore the stored Google account roster on launch
   - persist one selected destination calendar per Google account
   - track one last managed verification event per Google account
   - choose an active Google account for operations and live smoke automation
4. Patch `ContentView.swift`, `ConnectedAccountList.swift`, and `AccessibilityIDs.swift` to show:
   - an “Add Google account” action instead of a single reconnect-first mental model
   - one card per connected Google account with account identity, connection status, selected calendar picker, and test write/delete controls
   - account-specific remove/disconnect actions and clearer status copy suitable for UI automation and audit-trail logging
5. Add tests for:
   - secure account-store round trips
   - second-account connection without losing the first account
   - per-account calendar selection defaults and persistence
   - visible multi-account controls in the UI smoke path
6. Record or document the user-visible workflow for:
   - connect first Google account
   - add second Google account
   - select a calendar for each account
   - run create/delete verification for each account
7. Run:
   - `python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-19-google-calendar-live-integration-e2e.md`
   - `./scripts/build --platform macos`
   - `./scripts/build --platform all`
   - `./scripts/test-unit`
   - `./scripts/test-integration`
   - `./scripts/test-ui-macos --smoke`
   - `./scripts/test-ui-ios --device both --smoke`
   - the new live macOS E2E command
   - `python3 scripts/knowledge/check_docs.py`

## Validation and Acceptance

Acceptance means:

- the app can keep at least two Google accounts connected at the same time
- the app persists and restores the Google account roster across launches
- each connected Google account can load writable calendars independently
- the app persists and restores the selected destination calendar for each Google account
- the app can create a managed busy-slot event in the selected calendar for any connected Google account
- the app can delete that managed busy-slot event cleanly for any connected Google account
- the settings UI makes “add account”, “which account is selected”, and “which calendar belongs to which account” obvious without relying on reconnect semantics
- the macOS live smoke path completes with the `.env` test account and target calendar
- existing harness smoke tests still pass in scenario-backed mode

## Idempotence and Recovery

The live smoke event must be uniquely marked so reruns can clean up safely if a prior attempt left an event behind. Account-store writes must be atomic so a failed second-account connection cannot corrupt the existing roster. If live auth or external UI automation is flaky, the app should surface the failure explicitly on the relevant account card and the smoke runner should retry from a clean app session rather than silently passing.

If the provider-backed slice destabilizes the scenario harness, keep live functionality behind connected-account state and preserve the existing fixture-based launch path.

## Outcomes & Retrospective

Implemented:

- direct Google Calendar REST integration for writable-calendar discovery plus managed test-event create/delete
- a scenario-free live shell so the app can launch for real provider work without fixture arguments
- settings and audit-trail updates for macOS-only polling, Google calendar selection, and custom OAuth overrides
- a macOS live smoke runner plus accessibility hooks for auth, calendar selection, and managed-event round trips
- a macOS runtime guard that blocks Google sign-in from unsigned local harness launches and explains the signed-build requirement before the user enters the OAuth flow
- a secure multi-account Google roster backed by archived `GIDGoogleUser` sessions in the keychain
- a roster-based Google settings UI with add-account, remove-account, make-primary, per-account destination-calendar selection, and per-account verification controls
- connected-account summaries and audit entries that now reflect multiple live Google accounts instead of one mutable slot
- removal of stale SDK-session auto-import so launch restoration comes only from the app-owned roster
- signed macOS live smoke targeting by test account email plus Workspace domain, with `AXPress` accessibility actions instead of coordinate clicks

Validation completed:

- `./scripts/build --platform all`
- `./scripts/test-unit`
- `./scripts/test-integration`
- `./scripts/test-ui-macos --smoke`
- `./scripts/test-ui-ios --device both --smoke`
- `python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-19-google-calendar-live-integration-e2e.md`
- `python3 scripts/knowledge/check_docs.py`
- `./scripts/test-google-live-macos`

## Artifacts and Notes

- live smoke script: `scripts/test-google-live-macos`
- accessibility query helper: `scripts/lib/ax-query.swift`
- runtime artifacts remain under `artifacts/`
- the live verification event is written as a managed private busy slot with `calendarBusySyncManaged=true` and `calendarBusySyncKind=verification`
- screencast workflow to capture after implementation:
  - launch signed macOS build
  - add first Google account
  - add second Google account
  - select one destination calendar per account
  - run verification create/delete on both account cards

## Interfaces and Dependencies

- GoogleSignIn `9.1.0` provides session restore, sign-in, and refreshed access tokens, but only one SDK-managed `currentUser`
- Google Calendar REST v3 is used for calendar list and event CRUD over `URLSession`
- the live smoke harness depends on `.env` keys: `GOOGLE_CLIENT_PLIST_PATH`, `TEST_GOOGLE_USER`, `TEST_GOOGLE_USER_PASSWORD`, and `TEST_GOOGLE_CALENDAR_NAME`
- macOS UI automation depends on local Accessibility access plus `AXPress` via `scripts/lib/ax-query.swift`; `cliclick` remains as the fallback only when direct accessibility actions fail
