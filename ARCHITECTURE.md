# ARCHITECTURE.md

This document is the top-level codemap for the live repository. It names the major modules, boundaries, and cross-cutting concerns so a newcomer can navigate the repository without guessing.

## System overview

This repository is building a universal Apple-platform calendar busy-sync app with five major subsystems:

1. connected account management
2. calendar selection and routing
3. event normalization and sync planning
4. mirrored busy-slot writing and reconciliation
5. platform shells and harness tooling

The live codebase is still early. The Xcode project is not checked in yet, and most durable structure currently lives in the harness bootstrap layer.

## Top-level domains

### App shell

Purpose:

- host the app on macOS, iPhone, and iPad
- expose shared navigation, account configuration, and sync-status surfaces through platform-specific host adapters

Expected primary code area:

- `Calendar Busy Sync/Calendar Busy Sync/`

Stable concepts:

- `ConnectedAccount`
- `SelectableCalendar`
- `BusyMirrorRule`
- `MirrorCandidate`
- `MirrorWriteRequest`
- `HarnessLaunchOptions`
- `HarnessStateSnapshot`

### Sync domain

Purpose:

- normalize provider-specific event data into one internal busy/free model
- decide which selected calendars receive mirrored busy slots
- prevent recursive mirrors and duplicate holds

Expected primary code area:

- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Sync/`

### Provider adapters

Purpose:

- isolate Google Calendar, Apple EventKit, and future providers behind typed adapter boundaries
- own auth, token refresh, and provider payload decoding

Expected primary code area:

- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/`

### Tests and fixtures

Purpose:

- verify launch-option parsing, sync planning, mirror reconciliation, and UI accessibility contracts
- provide deterministic account/calendar/event fixtures for harness-driven launches

Expected primary code areas:

- `Calendar Busy Sync/Calendar Busy SyncTests/`
- `Calendar Busy Sync/Calendar Busy SyncUITests/`
- `Fixtures/scenarios/`
- `artifacts/` for runtime outputs only

### Harness and knowledge tooling

Purpose:

- provide shell-first build/test/capture entry points
- keep docs and repo-map artifacts current

Primary code areas:

- `scripts/`
- `docs/`
- `.agents/`
- `.codex/`

## Layering rules

- shared sync state and contracts stay in platform-neutral Swift files
- AppKit usage stays behind `#if os(macOS)` adapters
- UIKit usage stays behind `#if os(iOS)` adapters
- provider SDK or HTTP payload handling stays inside provider adapters
- shell scripts call shared helpers in `scripts/lib/`
- docs verification and repo-map generation use only standard Python 3 library modules

## Cross-cutting concerns

### Observability

The harness must be able to:

- launch the app deterministically from a canned sync scenario
- dump machine-readable state and perf snapshots
- capture app-owned screenshots
- identify key UI elements through stable accessibility identifiers

### Reliability

Critical commands should fail clearly when:

- Xcode is missing
- the shared scheme is absent
- the requested simulator device is unavailable
- required docs or plans are missing
- the app attempts to mirror to an unselected calendar

### Privacy and trust boundaries

If code changes affect:

- mirrored event payload shape -> update `docs/product-specs/calendar-sync.md`
- harness-visible command surface -> update `docs/harness.md`
- snapshot schema or accessibility identifiers -> update `docs/debug-contracts.md`
- architecture boundaries -> update this file
- workflow expectations -> update `AGENTS.md` and `README.md`
