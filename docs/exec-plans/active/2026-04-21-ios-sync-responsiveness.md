# iOS Sync Responsiveness

## Purpose / Big Picture

Keep the iPhone/iPad settings shell scrollable and interactive while a busy-mirror sync is running.

The current app launches sync work from `AppModel.syncNow()`, and `AppModel` is `@MainActor`. That is acceptable for short status updates, but the current implementation also performs synchronous Apple calendar reads and writes from that same main-actor loop. On iOS, a large reconciliation pass can therefore monopolize the UI thread long enough to make the app feel frozen.

This fix should preserve the current sync behavior while making the UI cooperative during long-running sync passes.

## Progress

- [x] 2026-04-21T19:24Z confirm the freeze source by tracing `ContentView` and `AppModel.syncNow()` on iOS
- [x] 2026-04-21T19:31Z add cooperative yielding in the iOS sync loop so foreground scrolling can continue during long sync passes
- [x] 2026-04-21T19:38Z validate the ExecPlan, iOS smoke flow, and docs checks; update durable notes
- [ ] 2026-04-21T19:38Z get a clean `./scripts/test-unit` pass after this slice; the runner rebuilt successfully but re-entered the recurring hosted XCTest post-launch hang

## Surprises & Discoveries

- 2026-04-21: the scroll view itself is not disabled during sync; the freeze comes from the main actor being occupied by sync work rather than a hit-testing overlay.
- 2026-04-21: Google provider calls are already async network operations and naturally yield, but Apple/EventKit sync work is synchronous and is currently invoked directly from the main-actor sync loop.
- 2026-04-21: a full off-main-actor rewrite would be riskier because `AppleCalendarService` is currently `@MainActor` and wraps `EKEventStore`; a cooperative-yield fix is the smallest safe first step.
- 2026-04-21: the repo's hosted macOS XCTest runner remains flaky; even after a successful rebuild, the test process can stall after launch with no additional output, so this slice leans on iOS smoke plus compile coverage from the test build.

## Decision Log

- 2026-04-21: prefer cooperative yielding inside the existing sync loop over a larger actor/service refactor so the change stays small and behavior-safe.
- 2026-04-21: scope the responsiveness fix to iOS, where the foreground scroll freeze is user-visible and macOS has less sensitivity to these pauses.

## Outcomes & Retrospective

- `AppModel.syncNow()` now cooperatively yields between participant enumeration and per-operation writes when running on iPhone or iPad, which keeps the main actor available often enough for the settings scroll view to remain interactive during long sync runs
- the fix is intentionally narrow: it does not change sync semantics or move `EventKit` off its current actor boundary
- targeted validation passed for the new ExecPlan, iOS smoke, and docs checks
- `./scripts/test-unit` was attempted twice after the change; the build/test host compiled successfully but the hosted XCTest runner again stalled after launch, so there is still an existing validation reliability issue outside this specific responsiveness patch

## Context and Orientation

Relevant files:

- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Apple/AppleCalendarService.swift`
- `Calendar Busy Sync/Calendar Busy Sync/ContentView.swift`
- `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`
- `.agents/DOCUMENTATION.md`

Current live state:

- `ContentView` continues to render a normal `ScrollView` while sync is in flight.
- `AppModel.syncNow()` is `@MainActor` and performs participant enumeration plus operation application serially.
- Apple calendar reads and writes are synchronous calls made directly from that main-actor loop.

## Plan of Work

1. Add a small iOS-only cooperative-yield hook inside the sync loop so long reconciliation runs periodically release the main actor.
2. Expose a narrow runtime signal or helper that can be unit-tested for platform gating.
3. Update durable notes so future work understands why the sync loop intentionally yields on iOS.

## Concrete Steps

1. Patch `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift` to:
   - define an iOS-only sync responsiveness helper
   - `await Task.yield()` between participant collection steps and between write operations when running on iOS
2. Patch `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift` with coverage for the platform gating that enables cooperative sync yielding on iOS but not macOS
3. Update `.agents/DOCUMENTATION.md` with the responsiveness finding and the chosen mitigation

## Validation and Acceptance

Run from `/Users/matthewmoore/Projects/calendar-busy-sync`:

```bash
python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-21-ios-sync-responsiveness.md
./scripts/test-unit
./scripts/test-ui-ios --device both --smoke
python3 scripts/knowledge/check_docs.py
```

Acceptance criteria:

- iOS sync runs no longer monopolize the main actor for the full duration of a long reconciliation pass
- the scroll view remains responsive enough to scroll while sync is still in progress
- macOS sync behavior remains unchanged

## Idempotence and Recovery

- adding cooperative yields is behavior-safe and idempotent; repeated sync runs follow the same create/update/delete logic as before
- if the change causes unexpected sequencing issues, rollback is limited to removing the yield helper from `AppModel.syncNow()`

## Artifacts and Notes

- manual verification:
  - launch the iOS app with multiple selected calendars and enough work to produce a visibly long sync
  - trigger `Sync Now`
  - attempt to scroll the settings view while the footer still shows active sync

## Interfaces and Dependencies

- SwiftUI main-actor view updates
- `Task.yield()`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Apple/AppleCalendarService.swift`
