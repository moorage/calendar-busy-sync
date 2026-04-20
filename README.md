# Calendar Busy Sync

Universal Apple-platform calendar busy-sync app for macOS, iPhone, and iPad.

The repository now contains a real universal SwiftUI app shell plus the Apple harness scripts and docs that drive local Codex work. The durable workflow lives in the files below:

- `AGENTS.md`
- `ARCHITECTURE.md`
- `.agents/PLANS.md`
- `docs/PLANS.md`
- `docs/product-specs/calendar-sync.md`
- `docs/harness.md`
- `docs/debug-contracts.md`

## Product summary

The app lets one person connect multiple calendar accounts, choose exactly which calendars in each account participate, and mirror only real busy commitments into all other selected calendars as busy hold blocks. A source event must both block time and represent an accepted commitment: self-owned events and no-attendee events mirror when busy, while invited events mirror only after the current user responds `Yes`. The goal is to prevent double-booking across multiple jobs, gigs, and companies without exposing full event details between accounts.

The main shell is now settings-first and compact: Google account management sits at the top, Apple / iCloud calendar selection follows, and lower-frequency controls live under Advanced. Each provider section uses a rounded gray settings panel with compact rows, refresh controls stay beside the calendar they affect, and provider status copy drops into small timestamped footnotes instead of full-width banners. On macOS, the app now runs as a menu bar utility with a launch-at-login toggle, a visible open-window state in the menu bar icon, no persistent Dock icon, and on-demand Settings and Logs windows. The footer keeps the live runtime status visible at all times, exposes `Logs` in its own dedicated window, and provides a `Sync Now` action without burning vertical space in the main form. Polling cadence is configurable on macOS only, defaults to every 2 minutes, and now lives under Advanced alongside audit-log retention and the toggle that lets a user bring their own Google OAuth app instead of relying on the product default.

The current implementation includes live Google Sign-In wiring for the default OAuth app declared in `.env` via `GOOGLE_CLIENT_PLIST_PATH`, a secure multi-account Google roster, writable-calendar loading per Google account, per-account selected-calendar persistence, and a real full-mesh busy-mirroring engine. The Google settings surface is organized around an account roster: add another account, see which accounts still need setup, choose one participating calendar per account, and remove an account without disturbing the rest of the roster. It also includes a live Apple / iCloud calendar path backed by EventKit: the user can grant calendar access, select a writable Apple calendar on the device, and include it in the same reconciliation set. Advanced custom OAuth mode is guarded: the user can supply their own native Google client ID only when it reuses the callback URL scheme baked into this build. Non-secret configuration now syncs across the app's macOS and iOS/iPadOS installs through iCloud key-value storage when the same Apple ID is signed in on those devices, and that shared-settings behavior can be turned off per device from Advanced.

## Quickstart

Prerequisites:

- full Xcode installed
- `xcodebuild`, `swift`, and `python3` available in Terminal
- iPhone and iPad simulators installed if you want simulator smoke coverage
- `.env` contains `GOOGLE_CLIENT_PLIST_PATH` pointing at a valid Google iOS/macOS OAuth plist for this bundle ID
- sign into the same Apple ID on each device if you want shared configuration through iCloud

Bootstrap and inspect the environment:

```bash
./scripts/bootstrap-apple
```

The bootstrap and build/test wrappers automatically sync the Google client plist from `.env` into:

- `Calendar Busy Sync/Info.plist`
- `Calendar Busy Sync/Calendar Busy Sync/DefaultGoogleOAuth.plist`

Build the app:

```bash
./scripts/build --platform all
```

For manual macOS Google auth testing, do not use the unsigned harness build in `artifacts/DerivedData`. Google Sign-In on macOS needs a development-signed app so it can persist OAuth state in the keychain, and the local Xcode Apple account must have valid credentials/provisioning for bundle ID `com.matthewpaulmoore.Calendar-Busy-Sync`.

Normal macOS launches now suppress the initial Settings window and rely on the menu bar item instead. The harness `--ui-test-mode 1` launch path intentionally keeps the Settings window visible so smoke automation can still operate on a deterministic surface.

Run narrow validation:

```bash
./scripts/test-unit
./scripts/test-ui-macos --smoke
./scripts/test-ui-ios --device iphone --smoke
./scripts/test-ui-ios --device ipad --smoke
./scripts/test-google-live-macos
```

Run the fast Codex loop:

```bash
./scripts/agent-loop
```

Capture a deterministic checkpoint:

```bash
./scripts/capture-checkpoint \
  --scenario basic-cross-busy.json \
  --platform-target macos \
  --checkpoint shell-smoke-macos
```

## Repo map

- `Calendar Busy Sync/` - expected Xcode project, app target, unit tests, and UI tests
- `Fixtures/` - deterministic sync-scenario fixtures for harness-driven launches
- `scripts/` - build, test, capture, docs, and knowledge tooling
- `docs/` - durable planning, product specs, harness contracts, and reliability/security docs
- `.agents/` - ExecPlan standard, execution runbook, and implementation notes
- `.codex/` - local Codex environment configuration

## Notes

- the sync engine should mirror only occupancy, not sensitive event details, unless the relevant product spec explicitly changes
- provider-specific SDK code belongs behind adapter boundaries; shared sync logic stays platform- and provider-neutral
- full-mesh mirroring is live for the selected calendars: only accepted busy commitments become an opaque `Busy` hold on every other selected calendar, and moved or deleted source events reconcile on the next sync pass
- invited events mirror only when the current user has responded `Yes`; tentative, declined, and pending/no-response events do not create mirror writes
- sync writes are future-only: past source time is never mirrored, and an already-in-progress source event is clipped so the mirrored busy hold starts at the current time
- Apple / iCloud mirrors now keep only a short human-readable note and store their recoverable identity behind a `calendarbusysync://mirror/<token>` URL marker plus app-local token mapping; older note-heavy mirrors migrate forward automatically and orphaned tokens are removed instead of duplicating busy holds
- shared configuration sync is limited to non-secret settings such as selected calendars and advanced preferences; Google account tokens and Apple permission state stay local to each device, and each device can opt out from Advanced without affecting the others
- the reconciliation scan still uses a bounded lookback plus the next 60 days so the app can clean up stale managed mirrors and catch in-progress events without scanning unbounded history
- the app now blocks macOS Google sign-in from unsigned local harness launches and tells the user to switch to a signed Xcode run when keychain-backed auth cannot work
- the macOS live Google smoke script now builds a signed app, targets `TEST_GOOGLE_USER` plus `TEST_GOOGLE_CALENDAR_NAME` from `.env`, and fails clearly when local Apple signing/account state prevents the OS/browser auth surface from opening
- `artifacts/` is runtime-only and ignored by git
