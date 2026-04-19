# Google Calendar Live Integration And E2E

## Purpose / Big Picture

Extend the existing Google Sign-In wiring into a real live Google Calendar integration that can:

- restore or establish a Google session on macOS, iPhone, and iPad
- enumerate writable calendars for the connected Google account
- let the user select which calendar in that account should receive writes
- create and delete a managed busy-slot event in the selected calendar
- drive a real macOS end-to-end smoke flow against the test account declared in `.env`

This slice does not implement the full cross-account mirroring engine yet. It delivers the first real provider-backed write path and proves the app can authenticate, resolve a target calendar, and safely round-trip an event create/delete cycle.

## Progress

- [x] 2026-04-19T01:20Z inspect the live-auth implementation and existing harness/test surfaces for the first provider-backed write slice
- [x] 2026-04-19T01:33Z add a Google Calendar provider layer for calendar list, event insert, and event delete using the signed-in user's refreshed access token
- [x] 2026-04-19T01:39Z patch the app model and settings UI so live calendar selection and managed event actions work alongside the scenario-backed shell
- [x] 2026-04-19T01:43Z add coverage for calendar decoding, selection persistence, and CRUD state transitions
- [x] 2026-04-19T01:52Z build a repeatable macOS end-to-end smoke runner that uses `TEST_GOOGLE_USER`, `TEST_GOOGLE_USER_PASSWORD`, and `TEST_GOOGLE_CALENDAR_NAME`
- [ ] 2026-04-19T01:55Z run build/test/docs verification, complete the live-auth round trip, then reconcile the documentation log and move completed plans out of `active/` - blocked by macOS `SafariLaunchAgent` cancelling the auth session before any browser UI appears

## Surprises & Discoveries

- 2026-04-19: the GoogleSignIn package already present in `DerivedData` exposes `GIDGoogleUser.accessToken.tokenString` and refresh helpers, so the app can call the Calendar REST API directly without adding a second Google API client library.
- 2026-04-19: the Xcode target already has `DEVELOPMENT_TEAM = GG34PA8F4A`, `CODE_SIGN_STYLE = Automatic`, and `CODE_SIGN_IDENTITY = Apple Development`, which means live macOS auth can be exercised with a signed debug build instead of the no-signing harness build.
- 2026-04-19: the current app still assumes a scenario fixture is always present at launch, so a live-provider workflow needs a safe empty-shell fallback instead of throwing a startup error when no scenario arguments are supplied.
- 2026-04-19: the no-signing harness build is sufficient for Google Calendar REST calls after authentication, but it is not sufficient evidence for the macOS auth handoff itself because the Google browser/session flow stalls before completion on this machine.
- 2026-04-19: `open -n ... --args` does not propagate environment variables into the app process, so the live smoke runner has to use `launchctl setenv` before launching the app.
- 2026-04-19: the first version of the live smoke script was too optimistic about UI readiness and exited before the Connect button appeared; the runner now waits for the control or relies on debug-only auto-sign-in.
- 2026-04-19: `scripts/lib/ax-query.swift` initially failed to compile under Swift 6 because of invalid `AXValue` downcasts, which made the live smoke script silently miss visible controls until the helper was fixed.
- 2026-04-19: the system auth logs are explicit now: `SafariLaunchAgent` starts the Google session and then records `User cancelled request with flags: 3` plus `Could not activate app with pid ...`, which is the concrete blocker for this machine's live macOS run.

## Decision Log

- 2026-04-19: keep the existing scenario-backed shell for previews and harness snapshots, but layer live Google account/calendar state on top instead of replacing the scenario model outright.
- 2026-04-19: use direct Calendar REST calls with `URLSession` and the GoogleSignIn access token rather than adding another heavy dependency for one read/write path.
- 2026-04-19: treat writable calendars as the first user-facing selection set, using Google Calendar `minAccessRole=writer` to avoid presenting read-only calendars that cannot accept mirrored busy slots.
- 2026-04-19: support a debug-only macOS live smoke mode that can auto-select the calendar named by the test environment and run create/delete once authentication completes, so end-to-end verification does not depend on brittle post-login UI clicking.
- 2026-04-19: trigger Google sign-in automatically when the app is launched in live smoke mode and no prior session is available, because the E2E harness should not depend on a race-prone initial button click.
- 2026-04-19: keep the live smoke launcher on `open -n` rather than executing the app binary directly so LaunchServices continues to deliver the OAuth callback URL to the correct app instance.

## Context and Orientation

Relevant files:

- `.env`
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/GoogleSignInService.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/ScenarioModels.swift`
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

## Plan of Work

1. Add Google Calendar provider types for writable calendar discovery and managed busy-event CRUD, including redacted API error handling and testable response decoding.
2. Expand `AppModel` with live calendar state, calendar-selection persistence, managed test-event lifecycle, and debug-only auto-run plumbing for a real smoke path.
3. Update the SwiftUI shell so the main surface remains settings plus audit trail, but now includes a live calendar picker and explicit create/delete actions once Google is connected.
4. Add unit and UI coverage for the new provider-backed surfaces and the empty-shell launch fallback.
5. Add a macOS end-to-end runner that launches a signed build, drives Google login with the `.env` credentials, waits for auto-selection of `TEST_GOOGLE_CALENDAR_NAME`, and verifies event create/delete success.
6. Run the relevant build/tests and docs/plan validators, then update `.agents/DOCUMENTATION.md` and reconcile active/completed ExecPlans.

## Concrete Steps

1. Create provider files under `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/` for:
   - calendar list decoding
   - event payload encoding/decoding
   - authenticated REST calls using the current Google user
2. Patch `ScenarioModels.swift` and `AppModel.swift` so the app can:
   - launch without scenario arguments
   - persist the selected live Google calendar ID
   - refresh the calendar list after sign-in or restore
   - track the last managed event create/delete operation
3. Patch `ContentView.swift` and `AccessibilityIDs.swift` to show:
   - the connected account and live calendar picker
   - refresh, create-test-event, and delete-test-event controls
   - clear status text suitable for UI automation and audit-trail logging
4. Add tests for:
   - empty-shell state generation
   - writable-calendar selection defaults
   - provider JSON decoding and error rendering
   - visible live controls in the UI smoke path
5. Add a macOS E2E script that:
   - loads `.env`
   - builds a signed debug app
   - launches the app in live smoke mode
   - uses AppleScript/System Events to complete the Google sign-in flow with `TEST_GOOGLE_USER` and `TEST_GOOGLE_USER_PASSWORD`
   - waits for the auto-run create/delete cycle to pass against `TEST_GOOGLE_CALENDAR_NAME`
6. Run:
   - `python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-19-google-calendar-live-integration-e2e.md`
   - `./scripts/build --platform all`
   - `./scripts/test-unit`
   - `./scripts/test-integration`
   - `./scripts/test-ui-macos --smoke`
   - `./scripts/test-ui-ios --device both --smoke`
   - the new live macOS E2E command
   - `python3 scripts/knowledge/check_docs.py`

## Validation and Acceptance

Acceptance means:

- a signed-in Google account can load writable calendars in the app
- the app persists and restores the selected Google calendar
- the app can create a managed busy-slot event in the selected calendar
- the app can delete that managed busy-slot event cleanly
- the macOS live smoke path completes with the `.env` test account and target calendar
- existing harness smoke tests still pass in scenario-backed mode

## Idempotence and Recovery

The live smoke event must be uniquely marked so reruns can clean up safely if a prior attempt left an event behind. If live auth or external UI automation is flaky, the app should surface the failure explicitly and the smoke runner should retry from a clean app session rather than silently passing.

If the provider-backed slice destabilizes the scenario harness, keep live functionality behind connected-account state and preserve the existing fixture-based launch path.

## Outcomes & Retrospective

Implemented:

- direct Google Calendar REST integration for writable-calendar discovery plus managed test-event create/delete
- a scenario-free live shell so the app can launch for real provider work without fixture arguments
- settings and audit-trail updates for macOS-only polling, Google calendar selection, and custom OAuth overrides
- a macOS live smoke runner plus accessibility hooks for auth, calendar selection, and managed-event round trips

Validation completed so far:

- `./scripts/build --platform all`
- `./scripts/test-unit`
- `./scripts/test-integration`
- `./scripts/test-ui-macos --smoke`

Still outstanding:

- `./scripts/test-ui-ios --device both --smoke`
- `python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-19-google-calendar-live-integration-e2e.md`
- `python3 scripts/knowledge/check_docs.py`
- a fully passing live Google auth round trip on this machine

The remaining blocker is the macOS Google auth handoff itself. The app reaches the sign-in call, but the browser/session UI never appears and the system logs show `SafariLaunchAgent` cancelling the request before activation can complete, so the live smoke path still needs machine-level auth-session remediation before it can pass end to end.

## Artifacts and Notes

- live smoke script: `scripts/test-google-live-macos`
- accessibility query helper: `scripts/lib/ax-query.swift`
- runtime artifacts remain under `artifacts/`
- the live verification event is written as a managed private busy slot with `calendarBusySyncManaged=true` and `calendarBusySyncKind=verification`

## Interfaces and Dependencies

- GoogleSignIn `9.1.0` provides session restore, sign-in, and refreshed access tokens
- Google Calendar REST v3 is used for calendar list and event CRUD over `URLSession`
- the live smoke harness depends on `.env` keys: `GOOGLE_CLIENT_PLIST_PATH`, `TEST_GOOGLE_USER`, `TEST_GOOGLE_USER_PASSWORD`, and `TEST_GOOGLE_CALENDAR_NAME`
- macOS UI automation depends on local Accessibility access plus `cliclick` and AppleScript/System Events
