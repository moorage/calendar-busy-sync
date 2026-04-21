# iOS Background Refresh

## Purpose / Big Picture

Implement a best-effort iPhone/iPad background refresh path so Calendar Busy Sync can opportunistically reconcile mirrored busy holds even when the app is not foregrounded.

This must not pretend iOS offers a fixed polling schedule. The product already states that iPhone and iPad cannot promise a strict cadence. The implementation therefore needs to:

- use Apple's background app refresh model instead of the macOS timer loop
- schedule future refresh requests opportunistically
- keep the same sync engine and provider boundaries
- surface clear user-facing status that this is best effort and OS-controlled
- stay inert for harness screenshot launches and UI-test launches

## Progress

- [x] 2026-04-21T05:33Z inspect the current app lifecycle, sync loop, and product/docs boundaries and confirm that iOS currently has no background refresh path
- [x] 2026-04-21T05:40Z add an iOS background refresh scheduler boundary, App lifecycle hooks, and app-model entry points for best-effort background reconciliation
- [x] 2026-04-21T06:15Z update the iOS settings/audit/docs/contracts surfaces and run targeted validation
- [x] 2026-04-21T06:52Z add a manual verification path that reuses the same iOS background refresh handler from a debug-only Advanced button and a simulator helper script

## Surprises & Discoveries

- 2026-04-20: the current app has no `BGTaskScheduler`, `BackgroundTasks`, or app/scene background lifecycle path at all; iOS only syncs during launch, explicit `Sync Now`, and foreground configuration changes.
- 2026-04-20: the current timed sync loop already lives behind `supportsPollingSettings`, which is macOS-only, so the safest rollout is additive rather than trying to reuse the timer on iOS.
- 2026-04-20: the generated `Info.plist` is rewritten by `scripts/sync-google-client-config.py`, so any background-refresh plist keys must be added there rather than patched only in the checked-in plist.
- 2026-04-21: the SwiftUI two-argument `onChange` overload would have forced an iOS 17 availability bump; the iOS 16 target needs the older single-argument closure form for `scenePhase`.
- 2026-04-21: the repo's existing `artifacts/DerivedData` warning still matters here; iOS build and smoke runs must stay sequential because parallel `xcodebuild` invocations lock the shared build database.
- 2026-04-21: `simctl` does not expose a simple stable public command for directly firing this app's `BGAppRefreshTask`, so the cleanest deterministic development probe is a one-shot launch environment flag that calls back into the exact same app-side refresh handler.

## Decision Log

- 2026-04-20: use `BGAppRefreshTask`, not `BGProcessingTask`, because this app needs short opportunistic reconciliation work rather than long-running background processing with additional power/network expectations.
- 2026-04-20: keep iOS cadence fixed as a best-effort scheduler hint owned by the app rather than exposing a user-configurable iOS polling interval.
- 2026-04-20: attach the iOS background refresh handler at the SwiftUI `Scene` layer and keep scheduling/state logic behind an injectable scheduler boundary so unit tests can verify behavior without talking to the real OS scheduler.
- 2026-04-20: skip background refresh scheduling for harness screenshot launches and UI-test launches so test automation remains deterministic and side-effect free.

## Outcomes & Retrospective

- the iOS build now schedules a best-effort `BGAppRefreshTask` request through an injectable scheduler boundary instead of having no background path at all
- the shared reconciliation engine still remains the only sync implementation; the background task simply calls back into `prepareIfNeeded()` plus `syncNowIfReady()`
- Advanced now shows iPhone/iPad background refresh status and explains that iOS chooses the actual timing
- debug iOS builds now also expose a `Run Refresh Path Now` control, and `./scripts/trigger-ios-background-refresh` reuses that same app-side refresh entry point on the simulator
- harness UI-test and screenshot launches stay deterministic because they suppress mobile background refresh scheduling entirely
- the generated `Info.plist` now carries `BGTaskSchedulerPermittedIdentifiers` plus `UIBackgroundModes` for background refresh
- iOS build and iPhone/iPad smoke validation passed after switching the scene-phase observer back to the iOS 16-compatible `onChange` overload

## Context and Orientation

Relevant files:

- `Calendar Busy Sync/Calendar Busy Sync/Calendar_Busy_SyncApp.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AuditTrail.swift`
- `Calendar Busy Sync/Calendar Busy Sync/ContentView.swift`
- `Calendar Busy Sync/Calendar Busy Sync/Harness/HarnessLaunchOptions.swift`
- `Calendar Busy Sync/Calendar Busy Sync/Harness/AccessibilityIDs.swift`
- `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`
- `Calendar Busy Sync/Info.plist`
- `scripts/sync-google-client-config.py`
- `README.md`
- `ARCHITECTURE.md`
- `docs/product-specs/calendar-sync.md`
- `docs/harness.md`
- `docs/debug-contracts.md`
- `.agents/DOCUMENTATION.md`

Current live state:

- macOS uses a timer-based sync loop controlled by `pollIntervalMinutes`
- iOS has no background scheduling path
- iOS sync happens only while the app is active
- the footer already reflects the latest sync result through `lastBusyMirrorSyncSummary`
- Advanced already diverges by platform, with macOS-only polling controls and no iOS background status surface

## Plan of Work

1. Add an iOS background refresh boundary that wraps scheduler availability, request submission, and cancellation behind a small injectable protocol.
2. Extend `AppModel` with iOS-only background refresh state plus methods to schedule refreshes, react to lifecycle transitions, and run the existing reconciliation flow from a background refresh task.
3. Wire `Calendar_Busy_SyncApp.swift` so the iOS scenes schedule refreshes when the app backgrounds, refresh availability on activation, and execute the best-effort background task handler.
4. Update the iOS Advanced surface, audit-trail builder, debug contracts, and docs to explain the new OS-controlled background behavior and its limits.

## Concrete Steps

1. Add a new iOS platform file under `Calendar Busy Sync/Calendar Busy Sync/App/Platform/iOS/` that defines:
   - the shared background refresh task identifier
   - an availability/status enum
   - a scheduler protocol with submit/cancel/availability methods
   - a default `BGTaskScheduler` implementation that submits `BGAppRefreshTaskRequest`
2. Patch `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift` to:
   - hold the injected scheduler dependency
   - expose a compact iOS background-refresh status summary for the Advanced view
   - schedule a new refresh request after preparation, after entering background, and after finishing a background refresh task
   - skip scheduling for screenshot-mode and UI-test launches
   - run `prepareIfNeeded()` plus `syncNowIfReady()` during the background refresh handler and record clear success/failure/disabled messages
3. Patch `Calendar Busy Sync/Calendar Busy Sync/Calendar_Busy_SyncApp.swift` to:
   - observe iOS `scenePhase`
   - trigger app-model lifecycle hooks for foreground/background transitions
   - add a SwiftUI `.backgroundTask(.appRefresh(...))` handler for iOS
4. Patch `scripts/sync-google-client-config.py` and `Calendar Busy Sync/Info.plist` to include:
   - `BGTaskSchedulerPermittedIdentifiers`
   - `UIBackgroundModes` with the app-refresh/fetch requirement used by the chosen API
5. Patch `Calendar Busy Sync/Calendar Busy Sync/ContentView.swift`, `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AuditTrail.swift`, and `Calendar Busy Sync/Calendar Busy Sync/Harness/AccessibilityIDs.swift` so iOS shows:
   - a compact Advanced row for background refresh status
   - explanatory copy that iOS decides the actual cadence
   - stable automation identifiers
6. Patch `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift` with coverage for:
   - scheduling suppression in test/screenshot modes
   - enabled/disabled/restricted status messaging
   - rescheduling after a successful or failed background refresh attempt
   - the manual verification surface reusing the same scheduler-backed refresh path
7. Update:
   - `README.md`
   - `ARCHITECTURE.md`
   - `docs/product-specs/calendar-sync.md`
   - `docs/harness.md`
   - `docs/debug-contracts.md`
   - `.agents/DOCUMENTATION.md`

## Validation and Acceptance

Run from `/Users/matthewmoore/Projects/calendar-busy-sync`:

```bash
python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-20-ios-background-refresh.md
./scripts/test-unit
./scripts/build --platform ios --device-class both
./scripts/test-ui-ios --device both --smoke
./scripts/trigger-ios-background-refresh --device iphone --skip-build
./scripts/build --platform macos
python3 scripts/knowledge/check_docs.py
```

Acceptance criteria:

- iPhone and iPad builds register and schedule a best-effort background refresh request without exposing a fake fixed interval control
- the iOS background refresh handler runs the existing reconciliation path rather than a forked sync implementation
- screenshot-mode and UI-test launches do not schedule background work
- the Advanced surface explains whether background refresh is available and that iOS decides actual timing
- debug builds provide a deterministic manual verification path that still exercises the real background refresh handler instead of a forked code path
- macOS behavior remains unchanged, including the existing timer-based loop and menu-bar shell

## Idempotence and Recovery

- scheduling the same refresh request repeatedly is safe as long as the implementation cancels/replaces the pending request before submitting a fresh one
- if background refresh is disabled or restricted on the device, the app should continue foreground/manual sync without error and show the disabled state clearly
- if the background task expires or fails, the app should mark the attempt as failed, reschedule the next best-effort request, and avoid wedging foreground sync
- rollback is straightforward: remove the iOS scheduler boundary, scene background task hook, and generated plist keys while keeping the existing foreground/manual sync path intact

## Artifacts and Notes

- future screencast path:
  - open the iOS build and show the Advanced row explaining best-effort background refresh
  - background the app, trigger a simulator background refresh event, and return to the app to show updated sync status
- Apple API/behavior notes to preserve in docs:
  - iOS background refresh timing is OS-controlled
  - the app provides only an earliest-begin hint
  - no user-visible promise of a fixed cadence should appear on iPhone or iPad

## Interfaces and Dependencies

- `BackgroundTasks.BGTaskScheduler`
- SwiftUI scene background task handling on iOS
- `UIApplication.backgroundRefreshStatus`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`
- `Calendar Busy Sync/Calendar Busy Sync/Calendar_Busy_SyncApp.swift`
- `scripts/sync-google-client-config.py`
- `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`
