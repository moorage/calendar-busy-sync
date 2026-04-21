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
- any source event that both blocks time and represents an accepted commitment becomes a mirrored busy hold on every other selected calendar
- self-owned busy events and busy events with no attendees count as accepted commitments
- invited events mirror only when the current user has responded `Yes`
- mirrored busy holds should contain only the minimum information required to block time unless a later product decision expands this
- free/available events do not create mirrored holds
- tentative, declined, and no-response invited events do not create mirrored holds
- moving, deleting, cancelling, or changing a source event to free/available must update or remove the mirrored holds on the next reconciliation pass
- if a selected destination calendar already has a busy event with the exact same start, end, and all-day state, the app must not create a second busy hold for that slot
- Apple / iCloud mirrors should not expose raw source identifiers in visible notes; their recoverable identity should stay opaque to the user while still letting the app update or delete them later
- non-secret configuration should sync across the app's macOS and iOS/iPadOS installs through iCloud when the same Apple ID is signed in, while provider auth tokens and device permission state remain local
- the shared iCloud settings payload should remember which Google account and selected destination calendar participate, so another device can offer a convenient local connect/remove handoff without syncing credentials

## Settings surfaces

- the main app shell should prioritize account management over a dense operational dashboard and keep low-frequency controls compact
- on macOS, the primary shell should live in the menu bar, with a Dock icon shown only while one of the app's windows is open
- audit trail should live in a separate window or dedicated surface instead of occupying the primary settings flow
- primary settings include connected Google accounts, Apple / iCloud calendar access on the current device, selected participating calendars, and the default shared Google OAuth configuration
- the persistent footer should expose current activity, pending work, failure count, a `Logs` launcher, and a `Sync Now` action
- the macOS menu bar item should expose `Open Settings`, `Open Logs`, `Sync Now`, and `Launch at Login`, and should visibly indicate when the Settings window is already open
- polling cadence is user-configurable on macOS only, with a default of every 2 minutes
- iPhone and iPad do not expose a user-configurable polling interval because background execution is not reliable enough to promise a strict schedule
- iPhone and iPad should still submit a best-effort background refresh request so iOS can opportunistically reconcile mirrored busy holds when the app is not foregrounded
- the current iOS background-refresh request should ask for no earlier than 15 minutes later, while explicitly treating that as an OS hint rather than a promise
- advanced settings include audit trail event log retention, macOS polling cadence, the option to disable shared iCloud settings on the current device, and the option to use a custom Google OAuth app instead of the product default
- advanced custom OAuth mode should allow the user to supply their own Google client identifiers so they can authorize against their own Google Cloud project
- custom native Google client IDs are only valid when the build already includes the matching reversed-client-ID callback scheme; otherwise the UI must block the flow and explain that a rebuild is required

## Current implementation slice

- the app can restore multiple previously connected Google accounts on launch from a secure store
- the settings surface can add another Google account and remove one account without disturbing the rest of the roster
- the harness syncs the default Google plist from `.env` into source-controlled app files before build/test runs
- the app can load writable calendars from each connected Google account and persist one selected participating calendar per account
- the app can request Apple calendar access through EventKit, load writable Apple / iCloud calendars from the current device, and persist the selected participating calendar
- the app can share non-secret configuration through iCloud key-value storage, including selected calendars and advanced preferences, while keeping Google account payloads and Apple permission state device-local
- the app can share a non-secret Google account descriptor roster through iCloud, letting another device show shared Google accounts that need local sign-in or local cleanup while preserving the selected calendar choice when possible
- each device can disable shared iCloud configuration locally without changing the shared-setting behavior of the user's other devices
- Google account handoff remains per-device: shared settings can tell a device which account/calendar should participate, but the device must still authorize the Google account locally before it can sync
- the iOS build now schedules a best-effort `BGAppRefreshTask` request and exposes its current background-refresh availability/state in Advanced, but still leaves actual execution timing up to iOS
- debug iOS builds now also expose a manual verification affordance for that same path, and the simulator harness can trigger it through a one-shot launch environment flag instead of inventing a second refresh implementation
- the app now reconciles the selected calendars as one participant set: accepted busy source events become opaque `Busy` holds on all the others, and moved/deleted/free/non-accepted source events update or delete the mirrored holds on the next pass
- reconciliation is exact-slot aware, so pre-existing busy occupancy and redundant app-managed duplicates suppress extra mirror writes instead of stacking duplicate busy events into the same slot
- Apple / iCloud mirrors now keep only a short note sentence visible to the user and move their recoverable identity into a URL marker plus app-local token mapping, with automatic migration of older note-heavy mirrors
- mirrored busy writes are future-only: past time is never written, and an ongoing source event is mirrored only from "now" through its end
- deselecting or disconnecting a participant calendar triggers cleanup of app-managed mirror events that were written into that calendar
- provider write-verification helpers may remain available for harness/debug automation, but they should not occupy the primary user-facing settings shell
- the macOS live smoke path now uses the `.env` test account plus calendar name to constrain Google auth, auto-select the target writable calendar, and complete the managed create/delete verification loop on a signed local build
- the macOS build now runs as an agent-style utility with `LSUIElement`, a `MenuBarExtra`, a launch-at-login wrapper over `SMAppService.mainApp`, explicit window-visibility tracking so the menu bar icon can reflect whether Settings is already open, and conditional Dock visibility plus foreground restoration so Settings and Logs behave like normal app windows once opened

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
- an invited event with RSVP `Maybe`, `No`, or no response does not create any mirrored busy slot
- disconnecting an account removes its calendars from future sync planning
- an exact matching busy slot on a selected destination calendar does not cause a second mirrored busy event to be created
- changing a selected participating calendar immediately cleans old mirror events from the deselected calendar and reconciles the newly selected participant set
- the configuration UI makes the selected participating calendars legible before sync runs
- Google auth state is visible in the settings shell with explicit add/remove account controls, per-account calendar selection, and clear custom-client validation

## Open decisions

- whether mirrored holds should preserve source duration edge cases such as all-day events or time-zone transitions exactly or through normalized local time blocks
- whether the first mirroring rollout should allow one selected Apple calendar per device or multiple Apple calendars at once
