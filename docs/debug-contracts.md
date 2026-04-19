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
- `accounts.add`
- `accounts.disconnect.<id>`
- `calendar-picker.account.<id>`
- `calendar-picker.calendar.<id>`
- `calendar-picker.include-toggle.<id>`
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
