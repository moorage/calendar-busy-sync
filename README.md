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

The app lets one person connect multiple calendar accounts, choose exactly which calendars in each account participate, and mirror any event that is not `free` / `available` into all other selected calendars as busy hold blocks. The goal is to prevent double-booking across multiple jobs, gigs, and companies without exposing full event details between accounts.

The main shell centers settings and audit history. Polling cadence is configurable on macOS only, defaults to every 2 minutes, and the settings surface now covers both live Google accounts and Apple / iCloud calendars available through EventKit. The Advanced area includes both audit-log retention and an override that lets a user bring their own Google OAuth app instead of relying on the product default.

The current implementation includes live Google Sign-In wiring for the default OAuth app declared in `.env` via `GOOGLE_CLIENT_PLIST_PATH`, a secure multi-account Google roster, writable-calendar loading per Google account, per-account selected-calendar persistence, and managed busy-slot create/delete verification from the settings shell. The Google settings surface is now organized around an account roster: add another account, see which accounts still need setup, choose one destination calendar per account, and remove an account without disturbing the rest of the roster. It also includes a live Apple / iCloud calendar path backed by EventKit: the user can grant calendar access, select a writable Apple calendar on the device, and run the same managed create/delete verification loop there. Advanced custom OAuth mode is guarded: the user can supply their own native Google client ID only when it reuses the callback URL scheme baked into this build.

## Quickstart

Prerequisites:

- full Xcode installed
- `xcodebuild`, `swift`, and `python3` available in Terminal
- iPhone and iPad simulators installed if you want simulator smoke coverage
- `.env` contains `GOOGLE_CLIENT_PLIST_PATH` pointing at a valid Google iOS/macOS OAuth plist for this bundle ID

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
- Google Sign-In plus writable-calendar loading and managed create/delete verification are live for multiple saved Google accounts, and Apple / iCloud calendar access now uses EventKit with the same destination-calendar verification loop; the full multi-account mirroring engine is still future provider work
- the app now blocks macOS Google sign-in from unsigned local harness launches and tells the user to switch to a signed Xcode run when keychain-backed auth cannot work
- the macOS live Google smoke script will fail clearly when local Apple signing/account state prevents the OS/browser auth surface from opening
- `artifacts/` is runtime-only and ignored by git
