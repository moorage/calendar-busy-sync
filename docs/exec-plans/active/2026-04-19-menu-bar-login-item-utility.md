# Menu Bar Login Item Utility

## Purpose / Big Picture

Convert the macOS build from a foreground Dock app into a menu bar utility that can optionally launch at login and stay out of the Dock during normal operation. The product should feel like a lightweight always-on calendar sync utility: the user sees sync state and quick actions from the menu bar, can open the main settings window on demand, and can enable or disable launch-at-login from the app itself.

This work is macOS-specific. iPhone and iPad keep the existing app shell. The sync engine, Google/iCloud provider adapters, and audit/log surfaces stay intact; the change is in app lifecycle, scene wiring, and macOS shell behavior.

## Progress

- [x] 2026-04-19T23:18Z capture the requested product direction and inspect the current app entrypoint, plist, and scene model so the plan can target the real shell files
- [x] 2026-04-19T23:34Z implement the macOS utility shell: `MenuBarExtra`, launch-at-login wrapper, open-window icon state, `LSUIElement` plist generation, and AppKit-backed initial Settings-window suppression outside harness UI-test launches
- [x] 2026-04-19T23:34Z update tests/docs/contracts and rerun focused validation; `build --platform macos`, `test-ui-macos --smoke`, ExecPlan validation, and docs validation passed
- [x] 2026-04-19T23:37Z restore unit-test compile health for the new shell model tests so the hosted macOS unit target at least builds cleanly again
- [x] 2026-04-20T01:30Z resolve the hosted macOS unit-test runner failure path by checking in an explicit shared scheme, skipping initial-window suppression during hosted XCTest startup, and updating the shell/status/planner tests so `./scripts/test-unit` now completes successfully
- [x] 2026-04-20T23:55Z keep menu-bar-opened windows in the foreground and switch Dock presence from "never shown" to "shown only while Settings or Logs is open", with matching shell-model regression coverage and doc updates
- [x] 2026-04-20T20:31Z rerun focused validation for the foreground/Dock change: `build --platform macos`, `test-ui-macos --smoke`, ExecPlan validation, and docs validation passed
- [x] 2026-04-20T20:39Z fix the hosted macOS unit-runner regression by disabling Dock-visibility policy changes in `hostedTests` runtime mode while keeping foreground activation behavior intact; `./scripts/test-unit` passes again and `test-ui-macos --smoke` still passes in standard mode

## Surprises & Discoveries

- 2026-04-19: the current app is a plain SwiftUI `WindowGroup` plus a second `WindowGroup` for audit trail, with no `MenuBarExtra`, no app delegate bridge, and no login-item wrapper yet.
- 2026-04-19: the current macOS build is unsigned for harness runs, but login-item registration and realistic menu bar behavior need validation on a signed local build because `SMAppService` and launch-at-login persistence are OS-managed behaviors.
- 2026-04-19: hiding the Dock icon is not just a visual tweak; once the macOS app runs as an agent-style utility, window activation, reopen behavior, and test automation entrypoints all need explicit handling.
- 2026-04-19: `defaultLaunchBehavior(.suppressed)` exists in the current SDK but is only available on macOS 15+, while the app still deploys to macOS 13. The implementation therefore uses an AppKit-backed one-time window suppressor to hide the initial Settings window on older supported systems.
- 2026-04-19: after the menu-bar shell landed, the unit target briefly failed to compile because a test fixture still used the old `GoogleAccountCardModel` initializer; fixing that exposed the deeper hosted-runner issue instead of leaving a fresh compile regression behind.
- 2026-04-20: the long-standing “host app launches, then XCTest never finishes” problem was two issues layered together: Xcode had no stable shared scheme checked in for the unit target, and the new one-time window suppressor needed to stay disabled during hosted XCTest startup.
- 2026-04-20: `MacUtilityShellModel` teardown is still fragile inside the app-hosted XCTest process on this toolchain, so the shell-model unit tests retain those helper instances for the lifetime of the test bundle instead of exercising XCTest's deallocation checker on them.
- 2026-04-20: suppressing the Dock icon full-time made Settings feel like it opened behind other apps even when the menu bar action succeeded; the missing piece was to promote the app back to `.regular` before opening the requested scene, then explicitly raise that window once AppKit has attached it.
- 2026-04-20: the hosted unit-runner regression came from one shell assumption leaking into the test host: forcing the app into accessory/no-Dock mode during `MacUtilityShellModel` initialization is fine for ordinary menu-bar launches, but it destabilizes the app-hosted XCTest environment. Gating Dock-policy changes behind runtime mode restored the host runner without undoing the user-facing shell behavior.

## Decision Log

- 2026-04-19: treat this as a macOS shell transformation, not a sync-domain feature. The sync engine should remain unchanged while the macOS presentation and launch behavior move to a menu bar utility model.
- 2026-04-19: prefer the modern `MenuBarExtra` + `SMAppService.mainApp` path on macOS 13+ rather than introducing a separate helper target unless implementation proves that a helper is required.
- 2026-04-19: the main settings UI should remain a normal window that can be opened from the menu bar, rather than trying to cram all configuration into the menu itself.
- 2026-04-19: Dock suppression should be macOS-only and reversible. The plan must preserve a rollback path to the current Dock-based app behavior if login-item or activation behavior becomes unstable.
- 2026-04-20: "not a persistent Dock app" means "no Dock icon when no app window is open", not "never show a Dock icon at all"; once Settings or Logs is visible, the app should behave like a normal foreground windowed app until the last window closes again.

## Outcomes & Retrospective

- the macOS app now boots as an `LSUIElement` menu bar utility instead of a persistent Dock app
- `MenuBarExtra` exposes `Open Settings`, `Open Logs`, `Sync Now`, `Launch at Login`, and `Quit Calendar Busy Sync`
- the menu bar icon switches to a filled variant while the Settings window is open so the user can tell the primary window is already visible
- opening Settings or Logs from the menu bar now promotes the app back into the foreground and shows a Dock icon for as long as either window remains open
- launch at login uses a typed wrapper over `SMAppService.mainApp`, with inline status messaging when the OS still requires approval
- a separate helper target was avoided in this slice
- the hosted macOS unit-test wrapper now finishes cleanly again, so the menu-bar shell is covered by `./scripts/test-unit` instead of relying only on build + UI smoke
- the remaining validation gap is true signed-build manual verification of launch-at-login persistence and Google OAuth callback behavior in the utility shell

## Context and Orientation

Relevant files and likely touch points:

- `Calendar Busy Sync/Calendar Busy Sync/Calendar_Busy_SyncApp.swift`
- `Calendar Busy Sync/Calendar Busy Sync/ContentView.swift`
- `Calendar Busy Sync/Calendar Busy Sync/AuditTrailView.swift`
- `Calendar Busy Sync/Calendar Busy Sync/AppSceneIDs.swift`
- `Calendar Busy Sync/Info.plist`
- `Calendar Busy Sync/Calendar Busy Sync.xcodeproj/project.pbxproj`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`
- `Calendar Busy Sync/Calendar Busy Sync/Harness/AccessibilityIDs.swift`
- `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`
- `Calendar Busy Sync/Calendar Busy SyncUITests/Calendar_Busy_SyncUITests.swift`
- `README.md`
- `ARCHITECTURE.md`
- `docs/product-specs/calendar-sync.md`
- `docs/debug-contracts.md`
- `.agents/DOCUMENTATION.md`

Current live state:

- macOS now exposes a `MenuBarExtra` plus on-demand Settings and Audit Trail windows
- the generated macOS plist includes `LSUIElement`, so the app starts without a persistent Dock icon and only shows one while an app window is open
- launch-at-login state is managed through `SMAppService.mainApp`
- harness `--ui-test-mode 1` launches intentionally keep the Settings window visible even though ordinary utility launches suppress the initial window

Target behavior:

- macOS shows a menu bar item with compact sync state and actions
- selecting the menu bar item lets the user open the settings window and logs window
- when the main settings window is open, the menu bar item should visibly reflect that state so the user can tell the utility is already showing its primary window
- the user can toggle launch at login from the app
- the macOS app does not sit in the Dock when no app windows are open, but it does appear in the Dock while Settings or Logs is visible
- iOS/iPadOS behavior remains unchanged

Assumptions to validate during implementation:

- macOS deployment remains high enough to use `MenuBarExtra` and `SMAppService.mainApp`
- an agent-style macOS app with `LSUIElement` can still present the existing settings and audit windows cleanly when opened from the menu bar
- UI smoke and harness launches can still find and interact with the settings window once the Dock icon is gone

## Plan of Work

1. Introduce a macOS utility-shell layer that separates menu bar lifecycle concerns from the shared app model and content views.
2. Add a launch-at-login service wrapper and persisted setting, then expose it in the macOS shell in a way that is user-visible but not mixed into iOS.
3. Convert the macOS scene graph so the main settings and audit windows open on demand from a menu bar extra instead of relying on the Dock app lifecycle.
4. Suppress the persistent Dock icon for the macOS app and explicitly manage activation/focus for settings/log windows.
5. Update tests, harness expectations, and docs so automation and repo guidance reflect the new menu bar utility model.

## Concrete Steps

1. Add a macOS-only lifecycle abstraction:
   - create a small shell layer under `Calendar Busy Sync/Calendar Busy Sync/` or `Calendar Busy Sync/Calendar Busy Sync/App/Platform/macOS/`
   - separate shared app model bootstrapping from macOS scene/lifecycle composition
   - decide whether `@NSApplicationDelegateAdaptor` is needed for activation policy and reopen behavior

2. Add the menu bar surface:
   - introduce a macOS-only `MenuBarExtra`
   - include quick read-only sync state, `Sync Now`, `Open Settings`, `Open Logs`, and `Launch at Login`
   - make the menu bar presentation show an explicit open-window state, such as a selected/alternate label or icon treatment, whenever the main settings window is already visible
   - keep provider configuration in the existing settings window instead of stuffing the menu with full forms

3. Add launch-at-login support:
   - introduce a typed wrapper around `SMAppService.mainApp`
   - add persisted launch-at-login state plus explicit error messaging if OS registration fails
   - decide whether this setting lives in `AppModel` or a macOS-specific shell model that bridges to it

4. Suppress Dock presence:
   - update the macOS app configuration to run without a persistent Dock icon, most likely through `LSUIElement` in `Calendar Busy Sync/Info.plist` or an equivalent macOS-only plist setting
   - add explicit code to open and foreground the settings/log windows from the menu bar, and temporarily restore Dock presence while those windows remain open
   - verify URL handling for Google auth still restores focus correctly when the app is an agent-style menu bar utility

5. Preserve discoverability and recovery:
   - add a clear menu item to open the main settings window at all times
   - keep `Logs` reachable from the menu bar as well as from the settings footer if that footer remains in the window
   - ensure there is still a reliable quit path in the menu bar item

6. Update automation and docs:
   - refresh `docs/debug-contracts.md` for any new menu bar or window-opening accessibility contracts
   - update UI smoke to open the settings window in the new macOS lifecycle if needed
   - update `README.md`, `ARCHITECTURE.md`, `.agents/DOCUMENTATION.md`, and `docs/product-specs/calendar-sync.md`
- record screencast steps for the new workflow:
  - launch the app
  - confirm there is no Dock icon until a window is opened
  - open the settings window from the menu bar
  - toggle launch at login
  - reopen Logs from the menu bar

## Validation and Acceptance

Acceptance means:

- on macOS, launching the app presents a menu bar item without keeping a normal Dock icon visible until a real app window opens
- the menu bar item can open the main settings window and the logs window reliably
- the menu bar item visibly indicates when the main settings window is already open
- opening Settings or Logs from the menu bar keeps that window in the foreground instead of dropping it behind other apps
- the Dock icon appears while Settings or Logs is open and disappears again once the last app window closes
- the user can enable and disable launch at login from the app, and the state reflects OS registration success
- `Sync Now` remains reachable without opening the settings window
- Google auth callbacks and Apple calendar permission flows still work when triggered from the menu bar utility context
- iOS and iPad behavior remain unchanged
- focused validation passes

Required validation commands from `/Users/matthewmoore/Projects/calendar-busy-sync`:

```bash
./scripts/build --platform macos
./scripts/test-ui-macos --smoke
python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-19-menu-bar-login-item-utility.md
python3 scripts/knowledge/check_docs.py
```

Additional manual validation expected on a signed macOS build:

```bash
open 'artifacts/DerivedDataSigned/Build/Products/Debug/Calendar Busy Sync.app'
```

Manual checks:

- confirm there is no Dock icon while no app windows are open
- confirm `Open Settings` and `Open Logs` foreground the correct windows
- confirm the Dock icon appears while Settings or Logs is visible and disappears after the last app window closes
- confirm the menu bar item changes appearance or state while the main settings window is open
- confirm toggling launch at login succeeds and survives relaunch
- confirm Google OAuth can still round-trip into the app

## Idempotence and Recovery

- rollout should avoid changing the sync engine or provider adapters unless utility-mode lifecycle exposes a real auth/activation bug
- if `LSUIElement` or menu-bar-only activation breaks auth, testing, or window recovery, the plan can temporarily keep the menu bar item while restoring normal Dock app behavior
- if `SMAppService.mainApp` proves unreliable in this target configuration, pause and record the outcome before introducing a helper target; do not silently broaden scope mid-implementation
- any macOS-only scene changes must remain behind `#if os(macOS)` so iOS/iPadOS builds keep the current app lifecycle

## Artifacts and Notes

- this is a user-visible workflow change and should end with a short screencast once implementation is stable
- menu bar automation may require different harness support than window-only smoke tests; treat that as an explicit validation slice rather than assuming the current smoke path still covers it
- unsigned harness builds may not be sufficient for realistic launch-at-login validation; signed-build evidence is expected here

## Interfaces and Dependencies

- depends on SwiftUI macOS scene APIs, especially `MenuBarExtra` and window-opening from scene IDs
- depends on Apple ServiceManagement for launch-at-login registration
- depends on `HarnessLaunchOptions` and the existing `AppModel` boot path continuing to work when the first visible surface is a menu bar item rather than a foreground window
- depends on the existing `AppSceneIDs.auditTrail` scene model, which should be reused instead of inventing a second logs surface
- depends on Google auth URL handling still reaching the app even when it runs as a menu bar utility
