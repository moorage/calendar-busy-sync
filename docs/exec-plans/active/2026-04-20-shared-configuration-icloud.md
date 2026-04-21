# Shared Configuration via iCloud

## Purpose / Big Picture

Let the macOS, iPhone, and iPad builds share non-secret app configuration through the same Apple account, so a user's selected participating calendars and advanced settings do not have to be re-entered on every device. The correct transport for this slice is iCloud key-value storage (`NSUbiquitousKeyValueStore`), not the keychain and not CloudKit. The synced payload must stay limited to preferences and selection state; Google auth payloads, access tokens, and device-local Apple permission state remain local.

## Progress

- [x] 2026-04-20T15:52Z inspect the current persistence boundaries in `AppModel`, `GoogleAccountStore`, and Apple calendar selection to identify which settings are safe to sync
- [x] 2026-04-20T16:10Z add an iCloud-backed shared configuration store, wire it into `AppModel`, and resolve remote changes against the current local state
- [x] 2026-04-20T16:25Z add portable Apple calendar selection matching, update docs, and run build/unit/UI/docs validation
- [x] 2026-04-21T09:18Z inspect the current iCloud shared-settings flow and confirm the visibility gap: the UI only exposes a static note, while `AuditTrailView` still renders synthesized status rows instead of real iCloud sync activity
- [x] 2026-04-21T09:40Z add explicit iCloud sync state, a manual sync trigger, and runtime log entries that record iCloud sync attempts/results in the Logs surface
- [x] 2026-04-21T10:05Z update tests/docs/debug contracts and run unit + iOS/macOS smoke validation for the new iCloud visibility flow
- [x] 2026-04-21T11:58Z move launch-time iCloud reconciliation off the iOS pre-first-frame path, keep the same shared-settings behavior during `prepareIfNeeded()`, and rerun unit + iOS smoke validation

## Surprises & Discoveries

- 2026-04-20: the existing app already has a clean boundary between local secrets and local settings: `GoogleAccountStore` uses the keychain for account payloads, while user preferences and selected calendar IDs live in `UserDefaults`. That makes iCloud key-value sync a safe additive layer instead of a storage rewrite.
- 2026-04-20: raw Apple `EKCalendar.calendarIdentifier` values are not a safe cross-device selection key, so Apple calendar sharing needs a portable reference built from the visible calendar/source identity rather than the device-local identifier alone.
- 2026-04-20: adding `com.apple.developer.ubiquity-kvstore-identifier` to the existing entitlements file was sufficient for both unsigned and signed builds; the signed macOS build continued to provision successfully under `Mac Team Provisioning Profile: com.matthewpaulmoore.Calendar-Busy-Sync`.
- 2026-04-21: the current “Logs” surface is not actually a runtime log. `AuditTrailBuilder` synthesizes categorized snapshot entries like “Google accounts connected” and “Writable Apple calendars”, which makes it hard to answer operational questions such as whether an iCloud shared-settings sync ever ran or failed.
- 2026-04-21: `NSUbiquitousKeyValueStore` already exposes `synchronize()`, so a manual iCloud sync affordance can stay inside the existing store abstraction instead of inventing a second transport path.
- 2026-04-21: `AppModel` was reconciling iCloud shared settings inside `init`, and `Calendar_Busy_SyncApp` also kicked off `prepareIfNeeded()` from `App.init` on iOS. That put `NSUbiquitousKeyValueStore.synchronize()` and other launch work ahead of the first SwiftUI frame, which manifested as a long white launch screen on iPhone/iPad.

## Decision Log

- 2026-04-20: sync configuration through `NSUbiquitousKeyValueStore` instead of CloudKit because the payload is small preference data and Apple explicitly positions key-value storage for shared settings/preferences.
- 2026-04-20: keep Google account tokens, archived `GIDGoogleUser` payloads, and Apple calendar authorization state out of iCloud sync; only replicate non-secret configuration and selection data.
- 2026-04-20: use a timestamped shared snapshot so launch and remote-change reconciliation can prefer the newest configuration instead of blindly overwriting local values.
- 2026-04-20: make the iCloud shared-settings toggle device-local so one device can opt out without disabling shared configuration across the user's other installs.
- 2026-04-21: expose iCloud shared-settings health as an explicit app state with `disabled`, `unavailable`, `syncing`, `succeeded`, and `failed` outcomes so the Advanced section and Logs window can answer whether sync happened.
- 2026-04-21: replace the old synthesized audit-trail overview rows with runtime log entries collected by `AppModel`, then append iCloud sync events, busy-mirror sync events, and provider message events into that stream instead of presenting categorized checkmark summaries.
- 2026-04-21: on iOS, defer launch reconciliation of iCloud shared settings until `prepareIfNeeded()` runs from the rendered root view instead of running shared-config I/O during `AppModel.init` / `App.init`.

## Outcomes & Retrospective

- Implemented `SharedAppConfiguration` under `Calendar Busy Sync/Calendar Busy Sync/App/Shared/SharedAppConfiguration.swift` using `NSUbiquitousKeyValueStore`, with protocol-backed observation and a timestamped full-snapshot payload.
- `AppModel` now reconciles shared settings at launch, publishes local edits to iCloud when available, and applies newer remote snapshots without looping local persistence.
- `AppModel` now also persists a local-only shared-settings toggle, so a device can stop publishing to and applying from iCloud while still keeping its own local preferences.
- Apple calendar selection now syncs through a portable `SharedAppleCalendarReference` so the same selected iCloud calendar can resolve on another device even when the raw EventKit identifier differs.
- The Advanced section now exposes explicit iCloud shared-settings health through `Off`, `Unavailable`, `Ready`, `Syncing…`, `Updated`, and `Failed` states, plus a manual `Sync iCloud Settings Now` button that appears only while the iCloud toggle is on.
- The Logs surface is now runtime-first for this flow: busy-mirror syncs, provider messages, startup outcomes, and iCloud shared-settings results append timestamped entries instead of showing categorized checkmark summaries that could not answer whether a sync actually ran.
- iOS launch no longer blocks the first frame on launch-time iCloud KVS work: `AppModel` now performs the same shared-settings reconciliation during `prepareIfNeeded()`, and the iOS app no longer starts `prepareIfNeeded()` from `App.init` before the root view renders.
- Validation passed with `./scripts/test-unit`, `./scripts/test-ui-ios --device both --smoke`, `./scripts/test-ui-macos --smoke`, `python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-20-shared-configuration-icloud.md`, and `python3 scripts/knowledge/check_docs.py`.
- A direct signed macOS build with `xcodebuild ... -allowProvisioningUpdates build` also succeeded, so the new iCloud KVS entitlement is compatible with the current Apple team provisioning setup.

## Context and Orientation

Today the app persists configuration directly in `UserDefaults` through `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`. The synced settings candidates are:

- polling interval
- audit trail retention
- Apple calendar enabled state
- selected Apple calendar reference
- custom Google OAuth override settings
- selected Google calendar IDs per connected account
- active Google account ID

The visibility gap to address in this extension is:

- the Advanced section currently exposes only a static iCloud note, not whether the last shared-settings sync succeeded or failed
- there is no manual iCloud sync action even when shared settings are enabled
- the Logs surface does not record actual iCloud sync attempts/results because it is built from categorized snapshots rather than runtime events

The settings that must stay local are:

- Google account roster payloads in `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/GoogleAccountStore.swift`
- any keychain-backed Google session data
- Apple calendar permission state from EventKit
- app-managed mirror identity token storage used for reconciliation recovery

The app currently has one entitlements file at `Calendar Busy Sync/Calendar_Busy_Sync.entitlements` for the universal target. iCloud key-value sync requires enabling the iCloud capability and the `com.apple.developer.ubiquity-kvstore-identifier` entitlement for the app target. Apple documents `NSUbiquitousKeyValueStore` as the preference-sharing mechanism for instances of the same app running on a person’s devices, and the iCloud capability page documents `com.apple.developer.ubiquity-kvstore-identifier` as the key-value storage entitlement.

## Plan of Work

1. Add a small shared-configuration module that can encode/decode a timestamped snapshot of sync-safe settings into `NSUbiquitousKeyValueStore`, observe remote changes, and stay testable through a protocol boundary.
2. Extend the Apple calendar selection model with a portable cross-device reference so a remote shared preference can resolve to the correct device-local EventKit calendar when available.
3. Wire `AppModel` so launch chooses the newest configuration between local `UserDefaults` and iCloud, local edits push to iCloud, and remote edits update the live UI plus sync planner without causing write loops.
4. Enable the iCloud key-value entitlement in the app target and document the resulting product behavior and limits.
5. Extend the same shared-configuration path with explicit sync status, a manual “Sync iCloud Settings Now” trigger, and runtime log entries so users can tell whether iCloud settings sync ran, applied remote data, published local data, or failed.

## Concrete Steps

1. Add a new shared settings file under `Calendar Busy Sync/Calendar Busy Sync/App/Shared/` that defines:
   - a timestamped `SharedAppConfiguration`
   - a portable `SharedAppleCalendarReference`
   - a protocol for shared configuration persistence/observation
   - a default `NSUbiquitousKeyValueStore` implementation
2. Patch `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Apple/AppleCalendarModels.swift` so Apple selection resolution can prefer:
   - a current device-local calendar ID when valid
   - otherwise a portable cross-device Apple calendar reference
   - otherwise the current iCloud/first-calendar fallback
3. Patch `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift` to:
   - load a persisted local last-modified timestamp
   - compare local settings to the shared iCloud snapshot at startup
   - push local edits into the shared store
   - observe remote iCloud changes and apply them without persistence loops
   - avoid syncing secrets or device-local provider state
4. Update `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift` with coverage for:
   - portable Apple selection matching
   - launch precedence between newer local vs newer shared configuration
   - remote shared settings changes updating `AppModel`
5. Enable the iCloud key-value capability in:
   - `Calendar Busy Sync/Calendar_Busy_Sync.entitlements`
   - `Calendar Busy Sync/Calendar Busy Sync.xcodeproj/project.pbxproj`
6. Update:
   - `README.md`
   - `ARCHITECTURE.md`
   - `docs/product-specs/calendar-sync.md`
   - `.agents/DOCUMENTATION.md`
7. Patch the current runtime surface:
   - `Calendar Busy Sync/Calendar Busy Sync/App/Shared/SharedAppConfiguration.swift`
   - `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`
   - `Calendar Busy Sync/Calendar Busy Sync/ContentView.swift`
   - `Calendar Busy Sync/Calendar Busy Sync/AuditTrailView.swift`
   - `Calendar Busy Sync/Calendar Busy Sync/Harness/AccessibilityIDs.swift`
   - `docs/debug-contracts.md`
8. Replace synthesized audit-trail rows with runtime log entries and add targeted tests in:
   - `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`
   - `Calendar Busy Sync/Calendar Busy SyncUITests/Calendar_Busy_SyncUITests.swift`

## Validation and Acceptance

Run from `/Users/matthewmoore/Projects/calendar-busy-sync`:

```bash
python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-20-shared-configuration-icloud.md
./scripts/test-unit
./scripts/build --platform ios --device-class both
./scripts/test-ui-ios --device both --smoke
./scripts/test-ui-macos --smoke
./scripts/build --platform macos
python3 scripts/knowledge/check_docs.py
```

Acceptance criteria:

- changing a shared preference on one device class can be represented in `NSUbiquitousKeyValueStore` and loaded by the app on another device class
- the app syncs only configuration/preferences, not Google tokens or other secret/session data
- Apple calendar selection can resolve across devices using a portable reference even when the raw EventKit calendar identifier differs
- when iCloud is unavailable, the app continues to use local `UserDefaults` without failing setup or sync
- when shared settings are enabled, the Advanced section exposes the current iCloud sync status plus a manual sync button
- the Logs surface records actual iCloud shared-settings sync attempts/results instead of only categorized overview rows
- iPhone and iPad harness smoke still pass after the new capability and startup sync path are added

## Idempotence and Recovery

- the shared payload is a full snapshot, so saving the same configuration repeatedly is safe
- remote updates older than the current local timestamp are ignored to avoid stale overwrites
- if iCloud key-value storage is unavailable or entitlement setup is missing on a device, the app continues with local settings only
- manual sync remains idempotent: if the local and shared snapshots already match, the app records that no newer changes were needed instead of mutating state again
- rollback is straightforward: remove the shared store wiring and entitlement, keep `UserDefaults` as the source of truth, and the app remains functional

## Artifacts and Notes

- future screencast path:
  - launch the app on macOS and iOS under the same Apple ID
  - choose a Google destination calendar on one device
  - relaunch the other device build and show the shared selection appearing there after refresh
- official references used to ground the entitlement choice:
  - Apple `NSUbiquitousKeyValueStore` docs
  - Apple “Configuring iCloud services” docs for `com.apple.developer.ubiquity-kvstore-identifier`

## Interfaces and Dependencies

- `Foundation.NSUbiquitousKeyValueStore`
- `NotificationCenter` for remote-change observation
- `UserDefaults` as the local fallback and timestamp store
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Apple/AppleCalendarModels.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`
- `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`
- `Calendar Busy Sync/Calendar_Busy_Sync.entitlements`
- `Calendar Busy Sync/Calendar Busy Sync.xcodeproj/project.pbxproj`
