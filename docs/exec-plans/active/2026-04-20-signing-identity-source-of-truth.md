# Signing Identity Source Of Truth

## Purpose / Big Picture

Make Apple signing configuration explicit and durable so local harness users know where the Sous Chef Studio team and distribution identity come from, and so App Store archive flows do not depend on ad hoc terminal history.

This work does not force the Apple Distribution certificate onto the existing signed macOS debug flow used for local Google OAuth checks. That path still depends on team-managed development signing plus an iCloud-capable development provisioning profile; directly forcing distribution there fails with the current target/provisioning setup.

## Outcomes & Retrospective

Completed outcomes:

- `.env` is now the repo-local source of truth for:
  - `APPLE_SIGNING_TEAM_ID`
  - `APPLE_DISTRIBUTION_SIGNING_IDENTITY`
  - `APPLE_DISTRIBUTION_SIGNING_SHA1`
- `scripts/lib/xcode-env.sh` now exposes shared helpers that load those values.
- `scripts/archive-appstore` now gives the repo one explicit App Store archive entry point for `macos` and `ios` that forces the configured distribution identity.
- `scripts/upload-appstore` now gives the repo an iOS App Store upload entry point that uses the verified exported `.ipa` plus the `.env` App Store Connect API key.
- docs and implementation notes now explain the split between:
  - signed debug builds for local OAuth/iCloud verification
  - distribution-signed archive work for App Store packaging

What changed from the original assumption:

- the repo already had the Sous Chef Studio team baked into the Xcode project, but that did not mean local signed debug builds would pick a Sous Chef Studio-named certificate
- directly forcing `Apple Distribution: Sous Chef Studio, Inc. (GG34PA8F4A)` onto the current signed debug build path is not compatible with the current iCloud-enabled automatic-signing setup, so the durable fix is a shared release/archive harness rather than pretending one identity can safely cover both flows today

## Context and Orientation

Relevant files:

- `scripts/lib/xcode-env.sh`
- `scripts/bootstrap-apple`
- `scripts/test-google-live-macos`
- `scripts/archive-appstore`
- `README.md`
- `docs/harness.md`
- `.agents/DOCUMENTATION.md`
- `.env`

Repository facts that shaped this work:

- the app target already carries `DEVELOPMENT_TEAM = GG34PA8F4A`
- the current signed macOS debug flow exists to support local Google OAuth and iCloud-enabled verification
- there was no durable repo script for App Store archive work, so release signing behavior was effectively living in terminal history instead of the harness

## Progress

- [x] 2026-04-20T19:45Z inspect the current signed build behavior and confirm that the app is provisioned under `GG34PA8F4A` but local debug builds are still using a development certificate
- [x] 2026-04-20T19:50Z prove that directly forcing `Apple Distribution: Sous Chef Studio, Inc. (GG34PA8F4A)` on the current automatic-signed debug build fails because the macOS iCloud-enabled target requires a different provisioning mode
- [x] 2026-04-20T20:00Z add `.env`-backed Apple signing helpers plus an App Store archive harness that forces the Sous Chef Studio distribution identity
- [x] 2026-04-20T20:05Z update harness/docs/implementation notes to explain where the local signing source of truth lives and why signed debug still uses team-managed development signing
- [x] 2026-04-20T20:15Z discover that direct manual-distribution archive overrides are the wrong provisioning mode for this target, then pivot the harness to the working Apple flow: automatic archive plus App Store export
- [x] 2026-04-20T20:20Z verify that the exported macOS package now lands on `Apple Distribution` with a `Mac Team Store Provisioning Profile` for the repo bundle ID
- [x] 2026-04-20T20:30Z verify that the iOS export lands on the same Apple Distribution SHA-1 and add a dedicated upload script backed by the `.env` App Store Connect API key

## Surprises & Discoveries

- 2026-04-20: the project already carries `DEVELOPMENT_TEAM = GG34PA8F4A`, but that does not guarantee which local signing certificate Xcode chooses for a signed debug build.
- 2026-04-20: the current signed macOS debug flow cannot simply be switched to the Sous Chef Studio distribution certificate from the command line. With the app's iCloud entitlement and current automatic-signing setup, Xcode rejects the override and/or requires a different provisioning profile.
- 2026-04-20: there was no repo-level archive harness, so previous App Store packaging depended on ad hoc commands instead of a durable scripted path.
- 2026-04-20: the successful macOS release path is not "force distribution at archive time"; it is "let Xcode archive with the working automatic-signing setup, then let App Store export re-sign the result onto Apple Distribution and the store provisioning profile."
- 2026-04-20: the same pattern holds for iOS; the exported `.ipa` already exposes the final Apple Distribution SHA-1 and store provisioning profile in `DistributionSummary.plist`, so upload should consume that verified artifact instead of raw archives.
- 2026-04-20: even after the archive path was scripted, the current machine still cannot complete a forced-distribution macOS archive without an iCloud-capable distribution provisioning profile for `com.matthewpaulmoore.Calendar-Busy-Sync`.

## Decision Log

- 2026-04-20: keep local signed debug builds on the working team-managed development-signing path so Google OAuth and iCloud-enabled local runs continue to work.
- 2026-04-20: treat `.env` as the local source of truth for the Apple team and the Sous Chef Studio distribution identity used by release/archive flows.
- 2026-04-20: because two Sous Chef Studio distribution certificates are installed locally, the exact distribution certificate source of truth must include SHA-1, not only the display name.
- 2026-04-20: add a dedicated `scripts/archive-appstore` entry point that drives the full App Store packaging flow; on macOS it must archive with automatic signing and then export for App Store distribution so the final package is Apple Distribution-signed.

## Plan of Work

1. Put Apple signing config behind shared shell helpers so every repo script resolves the same team and distribution identity values.
2. Replace hand-sourced `.env` logic in signed harness scripts with the shared helper path.
3. Add a first-class archive script for App Store packaging that forces the configured distribution identity.
4. Update the harness docs and implementation notes so the debug-vs-distribution split is explicit and discoverable.

## Concrete Steps

1. Extend `scripts/lib/xcode-env.sh` with:
   - `.env` loading
   - `apple_signing_team_id()`
   - `apple_distribution_signing_identity()`
   - `apple_distribution_signing_sha1()`
2. Update `scripts/test-google-live-macos` to use the shared env loader and team helper instead of hand-sourcing `.env`.
3. Add `scripts/archive-appstore` that:
   - accepts `--platform macos|ios`
   - archives with the team resolved from `.env`
   - exports the archive for App Store distribution
   - verifies the macOS export summary reports `Apple Distribution`
4. Add `scripts/upload-appstore` that:
   - accepts `--platform ios|macos`
   - builds via `scripts/archive-appstore` unless `--skip-build` is supplied
   - uploads the newest verified exported package with `xcrun altool`
   - authenticates from `.env` App Store Connect API key settings
4. Update `.env`, `scripts/bootstrap-apple`, `README.md`, `docs/harness.md`, and `.agents/DOCUMENTATION.md` so users know:
  - where the Sous Chef Studio distribution identity and exact SHA-1 are declared locally
   - how to discover it from the harness
   - why signed debug still does not force the distribution certificate

## Validation and Acceptance

Validation run:

- `zsh -n scripts/archive-appstore scripts/lib/xcode-env.sh scripts/test-google-live-macos scripts/bootstrap-apple`
- `./scripts/bootstrap-apple`
- `./scripts/build --platform macos`
- `./scripts/archive-appstore --platform macos`
- `./scripts/archive-appstore --platform ios`
- `./scripts/upload-appstore --platform ios`
- `python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-20-signing-identity-source-of-truth.md`
- `python3 scripts/knowledge/check_docs.py`

Acceptance means:

- the local Apple team/distribution identity can be discovered from `.env` through shared harness helpers
- repo users have one documented command for creating App Store archives with the Sous Chef Studio distribution identity
- docs no longer imply that any signed macOS build automatically uses the Sous Chef Studio distribution certificate

## Idempotence and Recovery

- rerunning the helper-backed scripts should continue to resolve the same team and distribution identity from `.env`
- the unsigned build/test harness remains unchanged and should still build without signing
- if the archive script fails because the local machine lacks the necessary distribution provisioning/profile state, that failure should be explicit and should not break the signed debug path
- restoring the previous behavior only requires removing the archive script and helper-backed docs; the local debug signing path remains independently viable

## Artifacts and Notes

- `.env` now contains the local Apple signing source of truth in addition to the existing App Store Connect and Google OAuth config
- `scripts/bootstrap-apple` now prints both the Apple team ID and the distribution identity so the local harness makes them easy to discover
- direct command-line forcing of the distribution identity against the current signed debug target was tested and documented as incompatible with the current iCloud-enabled automatic-signing setup
- the working macOS App Store output is now produced under `artifacts/exports/.../Calendar Busy Sync.pkg`, and `DistributionSummary.plist` confirms `Apple Distribution` signing, the exact configured SHA-1, and the store provisioning profile

## Interfaces and Dependencies

- depends on `xcodebuild` for build/archive orchestration
- depends on the local `.env` file for repo-local signing configuration
- depends on existing Apple account/provisioning state in Xcode for any real signed archive to succeed
- depends on repo docs and implementation notes staying aligned with the new helper-backed source of truth
