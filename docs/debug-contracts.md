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
- `--app-store-screenshot overview|mirrors|logs`
- `--app-store-screenshot-output <path>`
- `--platform-target macos|ios`
- `--device-class mac|iphone|ipad`

## Accessibility identifiers

Stable identifiers should include:

- `audit-trail.list`
- `audit-trail.open`
- `menu-bar.open-settings`
- `menu-bar.open-logs`
- `menu-bar.launch-at-login`
- `menu-bar.sync-now`
- `menu-bar.quit`
- `apple-calendar.status`
- `apple-calendar.message`
- `apple-calendar.connect`
- `apple-calendar.disconnect`
- `apple-calendar.open-settings`
- `apple-calendar.refresh`
- `apple-calendar.picker`
- `google-auth.message`
- `google-auth.resolution-warning`
- `google-auth.connect`
- `google-auth.connect-shared.<id>`
- `google-auth.disconnect.<id>`
- `google-auth.remove-shared.<id>`
- `google-calendar.status`
- `google-account.card.<id>`
- `google-calendar.message.<id>`
- `google-calendar.refresh.<id>`
- `google-calendar.picker.<id>`
- `google-calendar.live-smoke-status`
- `settings.sync.poll-interval`
- `settings.advanced.shared-configuration.enabled`
- `settings.advanced.google-oauth.use-custom`
- `settings.advanced.google-oauth.client-id`
- `settings.advanced.google-oauth.server-client-id`
- `sync-status.pending-count`
- `sync-status.failed-count`
- `sync-status.detail`
- `sync-status.sync-now`
- `mirror-preview.list`
- `mirror-preview.row.<id>`
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
- normal macOS utility launches suppress the initial Settings window and rely on the menu bar item; harness `--ui-test-mode 1` is the explicit exception that keeps the Settings window visible for smoke automation
- the live macOS Google smoke path reads `CALENDAR_BUSY_SYNC_LIVE_E2E=1`, `CALENDAR_BUSY_SYNC_E2E_ACCOUNT_EMAIL=<email>`, and `CALENDAR_BUSY_SYNC_E2E_CALENDAR_NAME=<name>` from the launch environment so the app can constrain Google auth to the expected Workspace domain, auto-select the intended writable calendar, and run the internal managed event verification loop
- multi-account Google UI is roster-based: harness and UI automation should treat Google controls as account-scoped using the `<id>` suffix rather than assuming a single global picker or disconnect button
- changing a selected participant calendar can trigger immediate cleanup and reconciliation, so harness-driven assertions should allow the sync status text to change without waiting for the macOS poll timer
- `scripts/lib/ax-query.swift` must support both value reads and `AXPress` actions so the live macOS Google smoke runner does not rely on brittle screen-coordinate clicks
- provider info rows now render as indented timestamped footnotes, so automation should anchor on the stable control IDs instead of matching those human-readable timestamps
- the macOS menu bar icon should shift to its “window open” state whenever the Settings window is visible, even though harness smoke continues to assert only the window-level controls
- App Store screenshot launches should render the requested view directly to the supplied PNG path and exit nonzero if the renderer cannot write the file
