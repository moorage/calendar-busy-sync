# iCloud Calendar Connection

## Purpose / Big Picture

Add a second live provider slice so the app can connect to Apple Calendar data on the device, with iCloud calendars as the primary user-facing target. The settings shell should let the user grant calendar access, choose a writable Apple/iCloud calendar, verify write access with a managed busy-slot create/delete loop, and keep the existing Google path intact.

This slice does not implement the full cross-provider mirroring engine yet. It delivers the Apple-side account/calendar selection and write-verification path the future sync planner will depend on.

## Progress

- [x] 2026-04-19T21:10Z inspect the current settings shell, provider boundaries, audit surfaces, and test harness for a second live provider
- [x] 2026-04-19T21:18Z add an Apple calendar provider layer for EventKit authorization, writable-calendar discovery, and managed busy-slot create/delete
- [x] 2026-04-19T21:27Z patch app state and persistence so Apple/iCloud connection state, selected calendar, and verification-event lifecycle survive relaunches
- [x] 2026-04-19T21:35Z update the SwiftUI settings, audit trail, and accessibility identifiers for the Apple/iCloud workflow
- [x] 2026-04-19T21:52Z add tests, run build/test/docs validators, update `.agents/DOCUMENTATION.md`, and record the user-visible workflow for future screencast capture

## Surprises & Discoveries

- 2026-04-19: the app shell already separates provider-specific state from the scenario-backed preview model, so Apple calendar support can land as a parallel provider slice instead of a larger shared-state refactor.
- 2026-04-19: EventKit authorization is device-wide, not account-scoped like Google OAuth, so an app-level "disconnect" must mean "stop using Apple calendars in this app" rather than revoking OS permission.
- 2026-04-19: iCloud calendars surface through EventKit as device calendars, so the UI should describe the area as Apple/iCloud calendars and show the underlying source title to make the chosen destination legible.
- 2026-04-19: modern Apple SDKs expose `requestFullAccessToEvents()` directly, but the compatibility path still needs an explicitly typed checked continuation for older `requestAccess(to: .event)` builds.
- 2026-04-19: the existing harness stayed deterministic without special-case resets because the Apple provider remains disconnected by default and `--ui-test-mode 1` does not auto-request permission.

## Decision Log

- 2026-04-19: use EventKit as the Apple provider boundary and present it in the product as "Apple / iCloud Calendar" rather than claiming a direct standalone iCloud auth flow.
- 2026-04-19: persist an app-level enablement flag plus selected Apple calendar ID so users can disconnect Apple calendars from this app without changing system Settings.
- 2026-04-19: mirror the existing Google verification pattern by supporting managed busy-slot create/delete for the selected Apple calendar, because that proves write access and keeps the provider surfaces symmetrical.

## Outcomes & Retrospective

Implemented:

- the app can request Apple calendar access
- the settings shell can load writable Apple/iCloud calendars from EventKit
- the user can choose which Apple/iCloud calendar participates
- the app can create and delete a managed verification busy slot in that calendar
- the audit trail and tests reflect the new provider path

Verification completed:

- `python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-19-icloud-calendar-connection.md`
- `./scripts/test-unit`
- `./scripts/build --platform all`
- `./scripts/test-integration`
- `./scripts/test-ui-macos --smoke`
- `./scripts/test-ui-ios --device both --smoke`
- `python3 scripts/knowledge/check_docs.py`

## Context and Orientation

Relevant files:

- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppSettings.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AuditTrail.swift`
- `Calendar Busy Sync/Calendar Busy Sync/ContentView.swift`
- `Calendar Busy Sync/Calendar Busy Sync/Harness/AccessibilityIDs.swift`
- `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`
- `Calendar Busy Sync/Calendar Busy SyncUITests/Calendar_Busy_SyncUITests.swift`
- `Calendar Busy Sync/Info.plist`
- `README.md`
- `ARCHITECTURE.md`
- `docs/product-specs/calendar-sync.md`
- `.agents/DOCUMENTATION.md`

Platform API references that shape the implementation:

- EventKit calendar authorization and event-store access on Apple platforms
- app privacy usage descriptions for calendar access in `Info.plist`

## Plan of Work

1. Add Apple provider types under `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Apple/` for authorization state, calendar summaries, selection resolution, and managed event records.
2. Add an EventKit-backed service that can request access, list writable calendars, and create/delete a verification busy slot while redacting low-signal failures into user-facing messages.
3. Expand `AppModel` with Apple provider state, persisted enablement/selection settings, reload-on-launch behavior, and audit-entry generation.
4. Update `ContentView.swift` and accessibility IDs so the Apple/iCloud workflow is visible and testable on macOS and iOS.
5. Add unit and UI coverage, run repository validation, and update durable docs plus the documentation log.
6. Leave a concrete screencast path documented for later capture: grant Apple calendar access, choose the Apple/iCloud calendar, create a test busy slot, then delete it.

## Concrete Steps

1. Create provider files under `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Apple/` for:
   - authorization state
   - writable calendar metadata
   - selection resolution
   - managed event record types
2. Implement an EventKit service that:
   - detects current authorization state
   - requests access when the user connects Apple/iCloud
   - returns writable event calendars with source labels
   - creates and deletes a managed private verification event
3. Patch `AppModel.swift` to:
   - persist Apple enablement and selected calendar ID
   - restore Apple provider state on launch
   - expose connect, disconnect, refresh, create-test-event, and delete-test-event actions
   - emit clear Apple/iCloud status/detail strings suitable for UI automation
4. Patch `ContentView.swift` and `Harness/AccessibilityIDs.swift` to show:
   - Apple/iCloud connection state
   - calendar picker
   - refresh/create/delete controls
   - source-aware detail text
5. Patch `Info.plist` with the required calendar usage description.
6. Add tests for:
   - selection resolution defaults
   - connect/disconnect persistence behavior
   - Apple authorization-denied messaging
   - UI smoke visibility of the Apple/iCloud controls
7. Run from `/Users/matthewmoore/Projects/calendar-busy-sync`:
   - `python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-19-icloud-calendar-connection.md`
   - `./scripts/build --platform all`
   - `./scripts/test-unit`
   - `./scripts/test-integration`
   - `./scripts/test-ui-macos --smoke`
   - `./scripts/test-ui-ios --device both --smoke`
   - `python3 scripts/knowledge/check_docs.py`

## Validation and Acceptance

Acceptance means:

- the app builds on macOS and iOS after the Apple provider slice lands
- the settings shell can request calendar access and surface denied/restricted/granted states clearly
- the app can load writable Apple/iCloud calendars and persist the selected destination calendar
- the app can create and delete a managed verification busy slot in the selected Apple/iCloud calendar
- the Google provider path and existing scenario-backed harness still work
- unit, integration, UI smoke, docs, and ExecPlan validation commands pass

## Idempotence and Recovery

The Apple verification event must be clearly marked so repeated runs can identify and remove it safely. Disconnecting Apple calendars from the app should clear in-app selection and managed-event state without mutating system calendar accounts.

If EventKit permission is denied or restricted, the UI must stay coherent and explain how to re-enable access from system Settings. If the Apple provider slice destabilizes the harness, keep the provider disabled by default and preserve the existing scenario-backed shell.

## Artifacts and Notes

- Apple calendar access requires a usage description in `Calendar Busy Sync/Info.plist`
- EventKit-backed calendar discovery is inherently device-dependent, so unit tests should rely on injected service doubles rather than the live event store
- future screencast capture should cover: connect Apple/iCloud, pick calendar, create test busy slot, delete test busy slot

## Interfaces and Dependencies

- depends on Apple `EventKit`
- depends on SwiftUI app lifecycle state in `Calendar_Busy_SyncApp.swift`
- depends on persisted settings in `UserDefaults`
- feeds the audit trail and settings shell in `ContentView.swift`
- must preserve existing Google provider behavior and scenario-driven harness artifacts
