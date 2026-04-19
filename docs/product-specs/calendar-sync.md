# Calendar Sync

## Snapshot

- Status: `planned`
- Platforms: `macOS`, `iPhone`, `iPad`
- Primary outcome: prevent double-booking across separately managed calendars without exposing sensitive event details

## User problem

People with multiple jobs, gigs, or companies often keep separate calendars per employer or client. They need each calendar to reflect that they are busy when another selected calendar already has a busy commitment, even though the underlying event details should stay private.

## Core behavior

- the app lets a user connect multiple calendar accounts
- when connecting an account, the user chooses exactly which calendars in that account participate in busy mirroring
- any source event that is not marked `free` / `available` becomes a mirrored busy hold on every other selected destination calendar
- mirrored busy holds should contain only the minimum information required to block time unless a later product decision expands this
- free/available events do not create mirrored holds

## Non-goals for the first slice

- full bi-directional event-detail sync
- attendee or conferencing propagation
- team-wide scheduling workflows
- support for calendars the user did not explicitly select

## Acceptance targets

- a two-account test scenario can show one busy event on account A appearing as a busy hold on selected calendars in account B
- a free/available event does not create any mirrored busy slot
- disconnecting an account removes its calendars from future sync planning
- the configuration UI makes the selected source and destination calendars legible before sync runs

## Open decisions

- whether mirrored holds should preserve source duration edge cases such as all-day events or time-zone transitions exactly or through normalized local time blocks
- whether the first release should support only Google Calendar or also include local Apple calendars
