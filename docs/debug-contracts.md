# Debug Contracts

This file freezes the harness-visible app contracts.

## Launch arguments

Supported debug launch arguments:

- `--scenario-root <path>`
- `--scenario <name>`
- `--window-size <width>x<height>`
- `--dump-visible-state <path>`
- `--dump-perf-state <path>`
- `--screenshot-path <path>`
- `--harness-command-dir <path>`
- `--ui-test-mode 1`
- `--platform-target macos|ios`
- `--device-class mac|iphone|ipad`

## Accessibility identifiers

Stable identifiers should include:

- `accounts.list`
- `audit-trail.list`
- `accounts.add`
- `accounts.disconnect.<id>`
- `apple-calendar.connection-status`
- `apple-calendar.status`
- `apple-calendar.message`
- `apple-calendar.connect`
- `apple-calendar.disconnect`
- `apple-calendar.open-settings`
- `apple-calendar.refresh`
- `apple-calendar.picker`
- `apple-calendar.create`
- `apple-calendar.delete`
- `apple-calendar.last-event`
- `google-auth.status`
- `google-auth.connected-account`
- `google-auth.message`
- `google-auth.resolution-warning`
- `google-auth.connect`
- `google-auth.disconnect.<id>`
- `google-calendar.status`
- `google-account.card.<id>`
- `google-account.primary.<id>`
- `google-calendar.message.<id>`
- `google-calendar.refresh.<id>`
- `google-calendar.picker.<id>`
- `google-calendar.create.<id>`
- `google-calendar.delete.<id>`
- `google-calendar.last-event.<id>`
- `google-calendar.live-smoke-status`
- `calendar-picker.account.<id>`
- `calendar-picker.calendar.<id>`
- `calendar-picker.include-toggle.<id>`
- `settings.sync.poll-interval`
- `settings.advanced.google-oauth.use-custom`
- `settings.advanced.google-oauth.client-id`
- `settings.advanced.google-oauth.server-client-id`
- `sync-status.last-run`
- `sync-status.pending-count`
- `sync-status.failed-count`
- `sync-status.run-now`
- `mirror-preview.list`
- `mirror-preview.row.<id>`
- `mirror-preview.source-calendar`
- `mirror-preview.target-calendar`
- `mirror-preview.busy-label`

## State snapshot

The app must be able to emit JSON with:

- `platform`
- `deviceClass`
- `selectedScenario`
- `connectedAccountCount`
- `selectedCalendarCount`
- `mirrorRuleCount`
- `pendingWriteCount`
- `failedWriteCount`
- `lastSyncStatus`
- `mirrorPreview`
- `mirrorPreview[*].sourceCalendar`
- `mirrorPreview[*].targetCalendar`
- `mirrorPreview[*].availability`

## Perf snapshot

The app must be able to emit JSON with:

- `platform`
- `deviceClass`
- `launchTime`
- `readyTime`
- `scenarioLoadTime`
- `syncPlanningTime`
- `mirrorPreviewCount`

## Harness commands

Planned stable harness commands include:

- `triggerManualSync`
- `exportMirrorLedger`

## Platform notes

- polling interval controls are exposed on macOS only
- iPhone and iPad builds still emit the same harness snapshots, but background sync cadence is not a user-configurable setting there
- the Google Sign-In callback URL is handled through the app lifecycle, but harness smoke launches stay scenario-backed and do not initiate interactive auth
- unsigned harness launches must block interactive macOS Google sign-in with explicit signed-build guidance, because the OAuth session relies on keychain persistence
- Apple / iCloud calendar access uses EventKit permission on the current device; harness `--ui-test-mode 1` launches must stay side-effect free and should not trigger permission prompts automatically
- the live macOS Google smoke path reads `CALENDAR_BUSY_SYNC_LIVE_E2E=1` and `CALENDAR_BUSY_SYNC_E2E_CALENDAR_NAME=<name>` from the launch environment so the app can auto-select a writable calendar and run the managed event create/delete verification
- multi-account Google UI is roster-based: harness and UI automation should treat Google controls as account-scoped using the `<id>` suffix rather than assuming a single global picker or disconnect button
