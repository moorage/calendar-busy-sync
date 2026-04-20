# Settings Shell IA Refresh

## Purpose / Big Picture

Reshape the main app window so it behaves like a settings-first productivity tool instead of a debug dashboard. The most common setup actions should stay near the top, duplicate explanatory copy should be removed, audit history should move out of the main surface, and the app should keep a persistent status line for live activity.

This work keeps the existing sync engine and provider integrations intact while changing how the user reaches them:

- put connect/add-account actions at the top and keep runtime actions in the persistent footer
- make per-provider calendar selection the main body of the window
- remove duplicate status/account summaries that repeat information already visible in the account cards
- move audit trail into a separate window/surface
- remove manual create/delete busy-slot controls from the main shell
- use icon-first labels where they improve scanability
- keep a persistent bottom status line showing current activity, pending activity, and failure count

## Progress

- [x] 2026-04-19T23:30Z capture the user-facing IA problems from the current shell and promote them into an executable refactor plan
- [x] 2026-04-20T03:05Z implement the main-window hierarchy refresh, remove duplicate sections, add icon-led actions, and replace the inline status block with a bottom status line
- [x] 2026-04-20T03:12Z move audit trail into a dedicated SwiftUI scene/window and replace the inline list with a launcher from the main shell
- [x] 2026-04-20T03:27Z update tests/docs/contracts and run focused validation; `build --platform macos`, `test-ui-macos --smoke`, ExecPlan validation, and docs validation passed
- [x] 2026-04-20T05:55Z flatten the remaining sections into a compact settings-pane layout, move polling into Advanced, shift `Sync Now` and `Logs` into the footer, and replace the Google header/action treatment with a roster-first row
- [x] 2026-04-20T06:15Z restore rounded gray section panels, add bundled Google/iCloud badges, remove the remaining header summary rows, move refresh actions onto the calendar rows, and timestamp the provider footnotes
- [x] 2026-04-20T07:50Z remove the leftover Google-account `Primary` affordance after confirming it no longer represented a meaningful product concept in the full-mesh roster
- [x] 2026-04-20T08:30Z refresh the hosted shell/status unit tests after the XCTest runner fix so the IA slice is again covered by `./scripts/test-unit`

## Surprises & Discoveries

- 2026-04-19: the current main window still contains both provider management cards and separate connected-account/status sections, so the duplication is structural rather than just wording-level.
- 2026-04-19: the main view still exposes manual create/delete provider verification buttons even though the product now has a real reconciliation engine and a separate live-smoke harness.
- 2026-04-20: after the first IA pass, the remaining visual noise came more from card styling and vertically stacked row content than from section count alone; the second pass needed flatter separators and single-line rows rather than more structural changes.
- 2026-04-20: flattening every section into divider-only rows went too far; once the redundant summaries were removed, the shell still needed rounded gray panels to preserve settings-pane scannability.
- 2026-04-20: the Google roster's old "Primary" account affordance had survived the multi-account refactor even though full-mesh mirroring no longer has a primary-account concept; it only added confusion.
- 2026-04-20: once the hosted macOS XCTest runner was fixed, the status-line tests needed to reflect the current shell behavior: when no live participant calendars are loaded, the footer now reports `Choose calendars to sync` even if stale stored Google accounts still exist.

## Decision Log

- 2026-04-19: the main window should optimize for setup and ongoing management, not provider-debug write actions.
- 2026-04-19: audit trail remains part of the product, but it should open in its own scene/window instead of consuming the primary settings surface.
- 2026-04-19: the bottom status line should summarize runtime state in compact form rather than repeat the long-form sync copy already shown in cards/messages.
- 2026-04-20: the footer, not the top of the form, should host `Sync Now` so the primary sections can stay focused on account/calendar configuration while runtime actions remain globally reachable.
- 2026-04-20: polling belongs under Advanced because it is a platform-specific tuning knob, not part of the core account-setup flow.
- 2026-04-20: provider refresh buttons belong on the same row as the calendar control they affect, and provider status copy should read as small timestamped footnotes rather than summary banners.
- 2026-04-20: the Google roster should not expose any account-level `Primary` action or badge because account order does not change sync semantics.

## Outcomes & Retrospective

- the main shell is now organized around Google account management, Apple / iCloud calendar selection, and advanced settings, with runtime actions kept in the persistent footer
- duplicate connected-account, status, and audit sections were removed from the primary window
- audit trail now opens in its own scene/window and remains backed by the same `auditTrailEntries`
- the main view no longer exposes manual create/delete busy-slot controls
- a persistent bottom status line now shows current activity, pending setup work, and failure count
- the second pass flattened the remaining sections into gray-divider rows, moved polling into Advanced, renamed the footer audit action to `Logs`, and kept `Sync Now` in the footer instead of a dedicated sync-controls block
- the latest pass restored rounded gray section panels, replaced the custom black Google mark with bundled Google/iCloud brand badges, removed the redundant Google/Apple summary lines, and added human-readable timestamps to the provider footnotes
- the latest pass also removed the stale Google `Primary` affordance so the roster only shows actions that change real sync behavior
- the hosted unit-test suite now covers the refreshed shell again; `./scripts/test-unit` completes successfully with the updated footer and shell-model expectations

## Context and Orientation

Relevant files:

- `Calendar Busy Sync/Calendar Busy Sync/ContentView.swift`
- `Calendar Busy Sync/Calendar Busy Sync/Calendar_Busy_SyncApp.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AuditTrail.swift`
- `Calendar Busy Sync/Calendar Busy Sync/Harness/AccessibilityIDs.swift`
- `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`
- `Calendar Busy Sync/Calendar Busy SyncUITests/Calendar_Busy_SyncUITests.swift`
- `README.md`
- `ARCHITECTURE.md`
- `docs/product-specs/calendar-sync.md`
- `docs/debug-contracts.md`
- `.agents/DOCUMENTATION.md`

Current live state:

- the main window mixes setup, status, debug verification actions, audit history, and duplicate account summaries into one long scroll
- audit trail is rendered inline in the main window
- sync status exists, but it is presented both as an in-page section and through repetitive provider messages
- Google and Apple account cards already contain the real management affordances, so a second connected-accounts section is redundant

## Plan of Work

1. Refactor the main shell around three levels of priority:
   - top: immediate actions and current readiness
   - middle: provider/account/calendar management
   - bottom: lower-frequency advanced controls and preview/debug-only surfaces
2. Move audit trail into a dedicated SwiftUI scene/window and leave only a lightweight launcher from the main shell.
3. Replace the current status block with a persistent bottom status line that surfaces current activity, pending work, and failures without extra narrative duplication.
4. Remove manual create/delete busy-slot buttons from the main shell and trim docs that still describe them as user-facing.
5. Add/update focused tests and refresh the durable docs.

## Concrete Steps

1. Patch `ContentView.swift` to:
   - reorder sections around setup and account management
   - remove duplicate connected-account and long-form status sections
   - remove manual provider create/delete controls
   - add icon-based section headers/buttons/chips where they improve scanability
   - add an audit-trail launcher instead of inline audit history
   - add a bottom status bar via a persistent inset
2. Add a dedicated audit-trail view and scene wiring in `Calendar_Busy_SyncApp.swift`.
3. Patch `AppModel.swift` to provide compact status-line state and any helper copy needed by the new hierarchy.
4. Update `AccessibilityIDs.swift` and UI tests for the new audit-trail launcher and bottom status line.
5. Update product/docs/control-plane files to remove stale references to manual create/delete controls and inline audit history.
6. Run:
   - `python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-19-settings-shell-ia-refresh.md`
   - `./scripts/test-unit`
   - `./scripts/test-ui-macos --smoke`
   - `python3 scripts/knowledge/check_docs.py`

## Validation and Acceptance

Acceptance means:

- the first visible controls are the sync/add-account/manage-calendar actions
- duplicate account and status summaries are gone from the main window
- audit trail no longer renders inline in the main view
- the main view no longer shows manual create/delete busy-slot controls
- icon usage improves scanability without adding decorative noise
- a persistent bottom status line shows current activity, pending activity, and failure count
- focused unit/UI/doc validation passes

## Idempotence and Recovery

- the refactor must not change sync semantics, selected-calendar persistence, or provider auth state
- moving audit trail into a dedicated scene must remain read-only and continue to use the existing `auditTrailEntries`
- removing main-window verification controls must not break the automated live Google smoke script or provider adapters

## Artifacts and Notes

- if the live-smoke or provider-debug create/delete helpers remain in code for automation, keep them internal and out of the primary user-facing shell
- prefer one coherent shell rewrite over a chain of tiny visual patches so the information architecture remains internally consistent

## Interfaces and Dependencies

- depends on the shared `AppModel` runtime state for sync, provider, and audit summaries
- depends on SwiftUI scene management for the dedicated audit-trail window
- depends on existing provider adapters and sync helpers remaining unchanged in behavior while the shell is reorganized
- depends on `docs/debug-contracts.md` and the UI smoke test continuing to agree on the exposed accessibility identifiers
