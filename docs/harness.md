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
- `./scripts/archive-appstore --platform macos`
- `./scripts/archive-appstore --platform ios`
- `./scripts/upload-appstore --platform ios`
- `./scripts/capture-appstore-screenshots-macos`
- `./scripts/capture-appstore-screenshots-ios`
- `python3 scripts/prepare-appstore-macos-submission.py --screenshot-dir artifacts/appstore/macos-screenshots`
- `python3 scripts/prepare-appstore-ios-submission.py --iphone-dir artifacts/appstore/ios-screenshots/iphone --ipad-dir artifacts/appstore/ios-screenshots/ipad`
- `./scripts/capture-checkpoint --scenario basic-cross-busy.json --platform-target macos --checkpoint shell-smoke-macos`
- `./scripts/agent-loop`
- `./scripts/verify-product-identity`

All build/test wrappers now run `scripts/sync-google-client-config.py` first. That script reads `.env`, loads `GOOGLE_CLIENT_PLIST_PATH`, copies the source Google plist into `Calendar Busy Sync/Calendar Busy Sync/DefaultGoogleOAuth.plist`, and regenerates `Calendar Busy Sync/Info.plist`.

The shared Xcode harness also treats `.env` as the local source of truth for Apple signing config:

- `APPLE_SIGNING_TEAM_ID`
- `APPLE_DISTRIBUTION_SIGNING_IDENTITY`
- `APPLE_DISTRIBUTION_SIGNING_SHA1`

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
- on macOS, keeping the Settings window visible during `--ui-test-mode 1` even though normal utility launches suppress that initial window in favor of the menu bar item
- honoring `--harness-command-dir <path>` for file-based smoke commands once write reconciliation exists

The scripts are responsible for:

- creating output directories
- syncing the Google OAuth plist declared in `.env` into the checked-in app paths before build/test work
- passing launch arguments or UI-test environment
- copying scenario fixtures into the simulator container when needed
- waiting for the snapshot files to exist
- surfacing missing prerequisites with concrete failure messages
- generating deterministic App Store screenshots under `artifacts/appstore/` when the release flow requests them

## Current scope

This harness currently covers local bootstrap, build, unit-test, integration-test, checkpoint capture, Google client-plist sync for the default auth configuration, the live Apple / iCloud EventKit settings slice, the macOS menu bar utility shell, and a macOS live Google smoke runner that drives the app through accessibility identifiers.

The live macOS smoke runner builds a signed macOS debug app, clears the app-owned Google roster, sets `CALENDAR_BUSY_SYNC_E2E_ACCOUNT_EMAIL` plus `CALENDAR_BUSY_SYNC_E2E_CALENDAR_NAME` from `.env`, and uses `AXPress` accessibility actions to drive the real Google auth handoff before the managed event create/delete round-trip. It uses the `.env` team value, but it intentionally stays on the working debug-signing path instead of forcing the distribution identity.

Manual macOS Google auth checks also need a signed app launch. The default harness build uses `CODE_SIGNING_ALLOWED=NO`, so it is suitable for build/test automation and scenario smoke work, but not for a browser-to-keychain Google sign-in round trip.

For App Store packaging, use `./scripts/archive-appstore`. That script forces the Sous Chef Studio distribution identity from `.env` and avoids depending on ad hoc terminal history for release/archive work.

For macOS, the script now follows the working Apple flow for this target: automatic archive, then App Store export. The exported package is verified through `DistributionSummary.plist` to use `Apple Distribution`, the exact certificate SHA-1 declared in `.env`, and a `Mac Team Store Provisioning Profile` for the repo bundle ID.

The release screenshot path intentionally uses an unsigned macOS build instead of the signed debug app. The signed app is sandboxed for the App Store path and cannot write PNG output back into the repo's `artifacts/` directory, so `./scripts/capture-appstore-screenshots-macos` builds the unsigned harness app and invokes the app-side screenshot renderer directly.

`scripts/prepare-appstore-macos-submission.py` then uses the App Store Connect API credentials from `.env` to populate the macOS version URLs, primary category, age rating, review contact, and screenshot set. If no valid macOS build matching the current App Store version exists yet, the script still uploads screenshots and other metadata and reports the missing-build condition clearly instead of failing early.

At the moment, macOS App Store export/upload still depends on a local `Mac Installer Distribution` certificate in Keychain Access. Without that installer certificate, the archive step succeeds but the App Store export cannot produce the `.pkg` needed for upload.

For iOS, `./scripts/capture-appstore-screenshots-ios` boots the preferred App Store screenshot simulators, launches the app in screenshot mode, and captures the iPhone and iPad PNG assets under `artifacts/appstore/ios-screenshots/`. `scripts/prepare-appstore-ios-submission.py` then attaches the latest valid `1.0` iOS build, fills in support/marketing URLs plus the shared review contact from `.env`, and uploads the `APP_IPHONE_67` and `APP_IPAD_PRO_3GEN_129` screenshot sets. The export/upload path still runs through `DistributionSummary.plist` verification before `scripts/upload-appstore` sends the `.ipa` to App Store Connect.
