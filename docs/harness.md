# Harness Guide

The harness is the shell-first control plane for this repository.

## Commands

- `./scripts/bootstrap-apple`
- `./scripts/build --platform all`
- `./scripts/test-unit`
- `./scripts/test-integration`
- `./scripts/test-ui-macos --smoke`
- `./scripts/test-ui-ios --device both --smoke`
- `./scripts/test-google-live-macos`
- `./scripts/capture-checkpoint --scenario basic-cross-busy.json --platform-target macos --checkpoint shell-smoke-macos`
- `./scripts/agent-loop`
- `./scripts/verify-product-identity`

All build/test wrappers now run `scripts/sync-google-client-config.py` first. That script reads `.env`, loads `GOOGLE_CLIENT_PLIST_PATH`, copies the source Google plist into `Calendar Busy Sync/Calendar Busy Sync/DefaultGoogleOAuth.plist`, and regenerates `Calendar Busy Sync/Info.plist`.

## Artifacts

Runtime artifacts live under `artifacts/`:

- `artifacts/xcodebuild/`
- `artifacts/checkpoints/`
- `artifacts/test-results/`

Checked-in scenario fixtures live under `Fixtures/scenarios/`.

## Capture flow

The app is responsible for:

- reading a deterministic sync scenario via `--scenario-root <path>` and `--scenario <name>`
- writing `state.json`
- writing `perf.json`
- writing `window.png`
- honoring `--ui-test-mode 1` so harness launches avoid live-provider side effects such as interactive Google auth or Apple calendar permission prompts
- honoring `--harness-command-dir <path>` for file-based smoke commands once write reconciliation exists

The scripts are responsible for:

- creating output directories
- syncing the Google OAuth plist declared in `.env` into the checked-in app paths before build/test work
- passing launch arguments or UI-test environment
- copying scenario fixtures into the simulator container when needed
- waiting for the snapshot files to exist
- surfacing missing prerequisites with concrete failure messages

## Current scope

This harness currently covers local bootstrap, build, unit-test, integration-test, checkpoint capture, Google client-plist sync for the default auth configuration, the live Apple / iCloud EventKit settings slice, and a macOS live Google smoke runner that drives the app through accessibility identifiers.

The live macOS smoke runner builds a signed macOS debug app, clears the app-owned Google roster, sets `CALENDAR_BUSY_SYNC_E2E_ACCOUNT_EMAIL` plus `CALENDAR_BUSY_SYNC_E2E_CALENDAR_NAME` from `.env`, and uses `AXPress` accessibility actions to drive the real Google auth handoff before the managed event create/delete round-trip.

Manual macOS Google auth checks also need a signed app launch. The default harness build uses `CODE_SIGNING_ALLOWED=NO`, so it is suitable for build/test automation and scenario smoke work, but not for a browser-to-keychain Google sign-in round trip.
