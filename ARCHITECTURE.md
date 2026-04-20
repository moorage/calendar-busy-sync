# ARCHITECTURE.md

This document is the top-level codemap for the live repository. It names the major modules, boundaries, and cross-cutting concerns so a newcomer can navigate the repository without guessing.

## System overview

This repository contains a universal Apple-platform calendar busy-sync app with five major subsystems:

1. connected account management
2. calendar selection and routing
3. event normalization and sync planning
4. mirrored busy-slot writing and reconciliation
5. platform shells and harness tooling

The live codebase is still early, but the Xcode project, harness shell, multi-account Google auth slice, Apple / iCloud EventKit slice, and first real mirror-reconciliation engine are checked in.

## Top-level domains

### App shell

Purpose:

- host the app on macOS, iPhone, and iPad
- expose shared navigation, account configuration, advanced OAuth settings, a dedicated audit-trail scene, and compact sync-status surfaces through platform-specific host adapters
- on macOS, present the product as a menu bar utility with launch-at-login control, on-demand windows, and no persistent Dock icon

Expected primary code area:

- `Calendar Busy Sync/Calendar Busy Sync/`

Stable concepts:

- `ConnectedAccount`
- `SelectableCalendar`
- `BusyMirrorRule`
- `MirrorCandidate`
- `MirrorWriteRequest`
- `AuditTrailEntry`
- `AppleCalendarSummary`
- `AppleManagedEventRecord`
- `GoogleOAuthOverrideConfiguration`
- `DefaultGoogleOAuthConfiguration`
- `ResolvedGoogleOAuthConfiguration`
- `GoogleConnectedAccount`
- `HarnessLaunchOptions`
- `HarnessStateSnapshot`

### Sync domain

Purpose:

- normalize provider-specific event data into one internal busy-plus-commitment model
- treat every selected calendar as both source and destination
- prevent recursive mirrors and duplicate holds
- reconcile a bounded sync window by comparing desired mirrors to provider-owned mirror metadata

Expected primary code area:

- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Sync/`

### Provider adapters

Purpose:

- isolate Google Calendar, Apple EventKit, and future providers behind typed adapter boundaries
- own auth, token refresh, and provider payload decoding

Expected primary code area:

- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/`

Current live slice:

- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Apple/`
- `AppleCalendarService` owns EventKit authorization, writable Apple-calendar discovery, source-event listing, and managed mirror create/update/delete for Apple / iCloud calendars on the current device
- `AppleMirrorIdentityStore` owns the local token-to-source mapping that backs Apple / iCloud mirror reconciliation without exposing raw source identifiers in visible notes
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/`
- `GoogleAccountStore` owns secure persistence of multiple Google sessions using archived `GIDGoogleUser` payloads
- `GoogleSignInService` owns restore/sign-in/disconnect, archived-session reauthorization, and platform presenter lookup
- `GoogleOAuthConfigurationResolver` enforces the current build's callback-scheme compatibility for custom native client IDs
- `GoogleCalendarService` owns writable-calendar discovery plus source-event listing and managed mirror create/update/delete through direct Calendar REST calls with the selected account's Google access token

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
- macOS-only polling controls stay behind platform-specific UI because iOS does not guarantee a fixed background schedule
- macOS menu bar lifecycle, window-visibility tracking, and launch-at-login logic stay behind `Calendar Busy Sync/Calendar Busy Sync/App/Platform/macOS/`
- provider SDK or HTTP payload handling stays inside provider adapters
- shell scripts call shared helpers in `scripts/lib/`
- Google client plist sync happens in `scripts/sync-google-client-config.py` before build/test commands
- accessibility-driven live smoke helpers live in `scripts/lib/ax-query.swift` and are used by the macOS Google E2E script
- docs verification and repo-map generation use only standard Python 3 library modules
- automatic reconciliation uses a bounded scan window with limited lookback plus the next 60 days so repeated sync passes remain idempotent without scanning unbounded history, while desired mirror writes themselves are clipped to present-and-future time only
- Apple / iCloud mirror identity recovery now uses a hybrid boundary: an on-event `calendarbusysync://mirror/<token>` URL marker plus app-local token persistence, with migration of older note-heavy mirror events and cleanup of orphaned markers

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
- the Google client plist declared in `.env` is missing or malformed
- the app attempts to mirror to an unselected calendar
- deselecting or disconnecting a participant calendar leaves stale mirror events behind
- the macOS menu bar utility fails to reopen its Settings or Logs windows once the Dock icon is suppressed

### Privacy and trust boundaries

If code changes affect:

- mirrored event payload shape -> update `docs/product-specs/calendar-sync.md`
- harness-visible command surface -> update `docs/harness.md`
- snapshot schema or accessibility identifiers -> update `docs/debug-contracts.md`
- Google auth flow, Apple calendar access, plist sync, or provider-boundary behavior -> update this file and `README.md`
- architecture boundaries -> update this file
- workflow expectations -> update `AGENTS.md` and `README.md`
