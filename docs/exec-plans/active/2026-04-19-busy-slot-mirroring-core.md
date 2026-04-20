# Busy-Slot Mirroring Core

## Purpose / Big Picture

Implement the first real sync engine for Calendar Busy Sync so the app does what the product promises instead of only proving provider connectivity.

This workstream changes the sync rule to the actual desired behavior:

- every selected calendar is both a source and a destination
- any event that is not `free` / `available` on one selected calendar must produce opaque busy holds on every other selected calendar
- if the source event moves, mirrored busy holds must move with it
- if the source event is deleted, cancelled, or no longer blocks time, mirrored busy holds must be deleted

The first implementation should reuse the current selected calendars:

- one selected writable calendar per connected Google account
- one selected writable Apple / iCloud calendar on the current device

Those selected calendars form one participant set. The engine reconciles mirrored busy holds across that set on demand and on a macOS timer.

This plan is promoted from `docs/ideas/backlog/busy-slot-mirroring-core.md` because the product rule and the first reconciliation approach are now accepted for implementation.

## Progress

- [x] 2026-04-20T01:40Z promote the busy-slot mirroring backlog brief into an executable plan that reflects the corrected product rule: all selected calendars mirror every other selected calendar
- [x] 2026-04-20T01:41Z add provider-neutral sync models plus provider adapter extensions for listing source events and reconciling managed mirror events
- [x] 2026-04-20T02:03Z implement app-level participant gathering, desired-write planning, mirror reconciliation, and macOS timer-driven sync
- [x] 2026-04-20T02:12Z update the settings shell, audit/status surfaces, selection-change cleanup, tests, and docs, then run validation

## Surprises & Discoveries

- 2026-04-20: the current live app already has enough provider surface to select one writable calendar per Google account plus one Apple / iCloud calendar, so the first sync engine can treat those selected calendars as the initial participant set without adding another calendar-selection workflow first.
- 2026-04-20: the simplest durable reconciliation approach is to store mirror metadata on the mirrored events themselves and rescan a bounded sync window, which avoids inventing a fragile local-only mirror mapping store.
- 2026-04-20: deselecting a participant calendar requires explicit cleanup of app-managed mirror events in the old destination calendar; otherwise those stale holds fall out of the selected participant set before the normal reconciliation pass can delete them.

## Decision Log

- 2026-04-20: every selected calendar is both source and destination; there is no separate per-calendar source toggle in the first sync engine.
- 2026-04-20: the first reconciliation engine will embed source identifiers in provider-owned mirror metadata and derive desired state from current source events on each sync run.
- 2026-04-20: the first rollout will use a bounded sync window for reconciliation rather than an unbounded historical sync; the exact horizon will be documented in code and product docs.
- 2026-04-20: verification create/delete buttons remain because they still prove provider write access independently of the automatic mirroring loop.

## Outcomes & Retrospective

- the app now automatically mirrors busy occupancy across all selected calendars in a bounded reconciliation window
- moving or deleting a source event causes mirrored holds to update or disappear on the next sync pass
- the settings shell now shows sync health and last-run state instead of only static configuration
- changing or disconnecting a participant calendar performs best-effort cleanup of stale app-managed mirror events in the deselected calendar before reconciling the new participant set

## Context and Orientation

Relevant files:

- `README.md`
- `ARCHITECTURE.md`
- `docs/product-specs/calendar-sync.md`
- `docs/ideas/backlog/busy-slot-mirroring-core.md`
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/GoogleCalendarService.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/GoogleCalendarModels.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/GoogleSignInService.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Apple/AppleCalendarService.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Apple/AppleCalendarModels.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AuditTrail.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/ConnectedAccountList.swift`
- `Calendar Busy Sync/Calendar Busy Sync/ContentView.swift`
- `Calendar Busy Sync/Calendar Busy Sync/Harness/AccessibilityIDs.swift`
- `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`
- `Calendar Busy Sync/Calendar Busy SyncUITests/Calendar_Busy_SyncUITests.swift`

Current live state:

- Google can sign in, restore multiple saved accounts, load writable calendars, list busy source events, and create/update/delete managed mirror events
- Apple / iCloud can request EventKit access, load writable calendars, list busy source events, and create/update/delete managed mirror events
- `AppModel` now gathers the selected participant calendars, runs reconciliation on demand plus on a macOS timer, and surfaces sync status in the main window

## Plan of Work

1. Add a provider-neutral sync domain under `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Sync/` for participant calendars, normalized busy source events, desired mirror writes, existing mirrored records, and reconciliation results.
2. Extend Google and Apple providers so each can:
   - list source events from the selected calendar in a bounded sync window
   - list existing managed mirror events in that selected calendar
   - create a managed mirror event for a source event
   - update an existing managed mirror event when the source time window changes
   - delete a managed mirror event that is no longer desired
3. Patch `AppModel.swift` so it can:
   - gather the selected participant calendars from the current Google roster plus Apple selection
   - run a reconciliation pass manually and on a macOS timer
   - surface last-run, pending-change, and failure state in the settings shell
4. Patch the SwiftUI shell so the app shows:
   - the real sync status
   - a manual `Sync Now` action
   - per-provider selection context that makes the participant set legible
5. Add tests for:
   - provider-neutral reconciliation planning
   - exclusion of managed mirror events from source scanning
   - update/delete behavior when a source event moves or disappears
   - app-model sync status transitions
6. Update durable docs and logs after the implementation stabilizes.

## Concrete Steps

1. Create shared sync models under `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Sync/`:
   - participant calendar identity
   - normalized source-event identity and busy window
   - mirrored-event metadata key format
   - reconciliation planner and result summaries
2. Extend `GoogleCalendarService.swift` to support:
   - listing busy source events from one selected Google calendar
   - listing existing managed mirror events from one selected Google calendar
   - creating, updating, and deleting managed mirror events with private extended properties that identify the source event and target calendar
3. Extend `AppleCalendarService.swift` to support:
   - listing busy source events from the selected Apple calendar
   - listing existing managed mirror events from the selected Apple calendar
   - creating, updating, and deleting managed mirror events with recoverable metadata stored in notes
4. Patch `AppModel.swift` to:
   - derive one participant set from all currently selected Google and Apple calendars
   - fetch current busy source events and existing mirror events
   - plan desired mirror state for every participant pair where source calendar != target calendar
   - reconcile creates, updates, and deletes
   - persist and surface last sync time, sync summary, and sync failures
   - start a macOS timer driven by `pollIntervalMinutes`
5. Patch `ContentView.swift` and `AccessibilityIDs.swift` to add:
   - `Sync Now`
   - visible last-run / pending / failed sync state
   - clearer wording that each selected calendar participates in full-mesh mirroring
6. Patch `AuditTrail.swift` and `ConnectedAccountList.swift` so they reflect:
   - selected participant calendars instead of destination-only wording
   - recent sync outcomes
7. Add or update tests in:
   - `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`
   - `Calendar Busy Sync/Calendar Busy SyncUITests/Calendar_Busy_SyncUITests.swift`
8. Run from `/Users/matthewmoore/Projects/calendar-busy-sync`:
   - `python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-19-busy-slot-mirroring-core.md`
   - `./scripts/test-unit`
   - `./scripts/test-integration`
   - `./scripts/test-ui-macos --smoke`
   - `./scripts/test-ui-ios --device both --smoke`
   - `python3 scripts/knowledge/check_docs.py`

Validation completed:

- `python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-19-busy-slot-mirroring-core.md`
- `./scripts/test-unit`
- `./scripts/test-integration`
- `./scripts/test-ui-macos --smoke`
- `./scripts/test-ui-ios --device both --smoke`
- `python3 scripts/knowledge/check_docs.py`

## Validation and Acceptance

Acceptance means:

- the selected Google and Apple calendars are treated as one participant set
- a busy source event on any participant calendar produces mirrored busy holds on every other participant calendar
- free or available events never produce mirror writes
- managed mirror events are excluded from source scanning so the app does not recurse on its own writes
- if a source event time window changes, the corresponding mirrored busy holds update on the next sync pass
- if a source event is deleted, cancelled, or becomes free, the mirrored busy holds delete on the next sync pass
- the app surfaces real sync status and a manual sync action in the main window
- macOS polling runs the same reconciliation logic on the configured interval
- unit, integration, UI smoke, docs, and ExecPlan validation commands pass

## Idempotence and Recovery

The reconciliation engine must be safe to rerun repeatedly:

- mirror metadata must uniquely identify the source event and source calendar
- rerunning sync with no upstream changes must produce no net writes
- deleting stale managed mirrors must only target events marked as app-managed mirror events
- if one provider write fails, the app should keep reconciling the rest of the participant set and surface the failure in sync status instead of silently stopping

Recovery approach:

- bounded sync-window scans rebuild desired state from the source calendars
- existing managed mirrors are discovered from provider metadata, not only from local process memory
- if the sync engine misbehaves, disabling a calendar by disconnecting its account or deselecting its participant calendar removes it from future planning without revoking provider credentials

## Artifacts and Notes

- first rollout should leave verification create/delete controls intact for debugging provider writes independently of the sync loop
- screencast flow to capture after implementation:
  - connect two Google accounts and Apple / iCloud if available
  - select one participant calendar per connected account/provider
  - create a busy event directly in one participant calendar
  - run `Sync Now` and show mirrored holds appear in the other selected calendars
  - move or delete the source event and show the mirrored holds update or disappear

## Interfaces and Dependencies

- depends on `GoogleSignIn` for access-token refresh and account restore
- depends on Google Calendar REST v3 for calendar/event listing plus event CRUD
- depends on Apple `EventKit` for Apple / iCloud event listing plus event CRUD
- depends on `UserDefaults` for selected-calendar persistence and sync settings
- depends on the current SwiftUI shell in `ContentView.swift`
- must preserve the deterministic scenario harness path for existing smoke tests
