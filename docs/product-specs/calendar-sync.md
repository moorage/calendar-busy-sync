# Calendar Sync

## Snapshot

- Status: `in progress`
- Platforms: `macOS`, `iPhone`, `iPad`
- Primary outcome: prevent double-booking across separately managed calendars without exposing sensitive event details

## User problem

People with multiple jobs, gigs, or companies often keep separate calendars per employer or client. They need each calendar to reflect that they are busy when another selected calendar already has a busy commitment, even though the underlying event details should stay private.

## Core behavior

- the app lets a user connect multiple calendar accounts
- when connecting an account, the user chooses exactly which calendars in that account participate in busy mirroring
- any source event that is not marked `free` / `available` becomes a mirrored busy hold on every other selected calendar
- mirrored busy holds should contain only the minimum information required to block time unless a later product decision expands this
- free/available events do not create mirrored holds
- moving, deleting, cancelling, or changing a source event to free/available must update or remove the mirrored holds on the next reconciliation pass

## Settings surfaces

- the main app shell should prioritize settings and an audit trail over a dense operational dashboard
- primary settings include connected Google accounts, Apple / iCloud calendar access on the current device, selected participating calendars, and the default shared Google OAuth configuration
- polling cadence is user-configurable on macOS only, with a default of every 2 minutes
- iPhone and iPad do not expose a user-configurable polling interval because background execution is not reliable enough to promise a strict schedule
- advanced settings include audit trail event log retention and the option to use a custom Google OAuth app instead of the product default
- advanced custom OAuth mode should allow the user to supply their own Google client identifiers so they can authorize against their own Google Cloud project
- custom native Google client IDs are only valid when the build already includes the matching reversed-client-ID callback scheme; otherwise the UI must block the flow and explain that a rebuild is required

## Current implementation slice

- the app can restore multiple previously connected Google accounts on launch from a secure store
- the settings surface can add another Google account, remove one account without disturbing the rest of the roster, and mark one account as the primary live-verification context
- the harness syncs the default Google plist from `.env` into source-controlled app files before build/test runs
- the app can load writable calendars from each connected Google account and persist one selected participating calendar per account
- the app can request Apple calendar access through EventKit, load writable Apple / iCloud calendars from the current device, and persist the selected participating calendar
- the app now reconciles the selected calendars as one participant set: busy source events become opaque `Busy` holds on all the others, and moved/deleted/free source events update or delete the mirrored holds on the next pass
- deselecting or disconnecting a participant calendar triggers cleanup of app-managed mirror events that were written into that calendar
- the settings surface still exposes create/delete verification actions so provider write access can be checked independently of the automatic sync loop
- the macOS live smoke path now uses the `.env` test account plus calendar name to constrain Google auth, auto-select the target writable calendar, and complete the managed create/delete verification loop on a signed local build

## Defaults

- macOS polling interval: every 2 minutes
- macOS audit trail retention: unlimited
- iPhone and iPad audit trail retention: last 1000 events
- Google OAuth mode: shared default app unless the user opts into custom credentials
- Apple / iCloud Calendar mode: off until the user connects it from settings

## Non-goals for the first slice

- full bi-directional event-detail sync
- attendee or conferencing propagation
- team-wide scheduling workflows
- support for calendars the user did not explicitly select

## Acceptance targets

- a two-account test scenario can show one busy event on account A appearing as a busy hold on selected calendars in account B
- a free/available event does not create any mirrored busy slot
- disconnecting an account removes its calendars from future sync planning
- changing a selected participating calendar immediately cleans old mirror events from the deselected calendar and reconciles the newly selected participant set
- the configuration UI makes the selected participating calendars legible before sync runs
- Google auth state is visible in the settings shell with explicit add/remove account controls, per-account calendar selection, and clear custom-client validation

## Open decisions

- whether mirrored holds should preserve source duration edge cases such as all-day events or time-zone transitions exactly or through normalized local time blocks
- whether the first mirroring rollout should allow one selected Apple calendar per device or multiple Apple calendars at once
