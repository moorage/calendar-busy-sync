# Initial Apple App And Smoke Path

## Purpose / Big Picture

Stand up the first real macOS/iOS app project for Calendar Busy Sync and implement the minimum harness-aware scenario load, state dump, perf dump, and screenshot path so the repo's Apple scripts build and validate real code.

## Progress

- [x] 2026-04-18T23:44Z inspect the harness contracts, available Apple tooling, and the source project's Xcode target structure
- [x] 2026-04-18T23:50Z create a minimal universal Xcode project plus app, unit-test, and UI-test targets
- [x] 2026-04-19T00:08Z implement launch parsing, canned scenario loading, mirror preview generation, and artifact writing
- [x] 2026-04-19T00:36Z run the build, unit, integration, and smoke harness commands and reconcile failures

## Surprises & Discoveries

- 2026-04-18: the local machine has Xcode and Swift installed, but not `xcodegen` or `tuist`, so the safest automation path is a hand-authored minimal `pbxproj`.
- 2026-04-19: the first boot for fresh iPhone and iPad simulators spends ~30-45 seconds in data migration before the smoke harness can install and capture artifacts.
- 2026-04-19: concurrent `xcodebuild` invocations that share `artifacts/DerivedData` can fail with a locked build database, so Apple harness commands should run sequentially.

## Decision Log

- 2026-04-18: use a fresh minimal file-system-synchronized Xcode project instead of copying the entire markdown viewer target, because the target graph is reusable but the source app's package dependencies and feature surface are not.
- 2026-04-19: satisfy the current screenshot contract with a deterministic synthetic PNG written by the app instead of adding platform-specific real-window capture code before sync features exist.
- 2026-04-19: keep the first app slice scenario-backed and offline, with mirror previews derived from fixture data instead of provider SDK integration.

## Outcomes & Retrospective

Implemented a working universal SwiftUI app project with:

- shared scenario loading and mirror-preview derivation from `Fixtures/scenarios/basic-cross-busy.json`
- harness launch-argument parsing for scenario selection and output paths
- artifact emission for `state.json`, `perf.json`, and `window.png`
- unit, integration, and UI tests aligned to the repo harness scripts

Validation completed successfully with:

- `./scripts/bootstrap-apple`
- `./scripts/build --platform all`
- `./scripts/test-unit`
- `./scripts/test-integration`
- `./scripts/test-ui-macos --smoke`
- `./scripts/test-ui-ios --device both --smoke`

The only noteworthy operational issue was Xcode's shared build database lock when multiple harness commands were run in parallel against the same `DerivedData` directory. Running them sequentially resolves it cleanly.

## Context and Orientation

Relevant files:

- `Calendar Busy Sync/Calendar Busy Sync.xcodeproj/project.pbxproj`
- `Calendar Busy Sync/Calendar Busy Sync/`
- `Calendar Busy Sync/Calendar Busy SyncTests/`
- `Calendar Busy Sync/Calendar Busy SyncUITests/`
- `Fixtures/scenarios/basic-cross-busy.json`
- `scripts/build`
- `scripts/test-unit`
- `scripts/test-integration`
- `scripts/test-ui-macos`
- `scripts/test-ui-ios`

The app only needs to satisfy the current harness contracts from `docs/debug-contracts.md`, not full provider-backed sync.

## Plan of Work

1. Create a small universal SwiftUI app project with app, unit-test, and UI-test targets.
2. Implement shared scenario models and mirror-preview generation from the canned JSON fixture.
3. Implement the harness-visible launch options, state snapshot, perf snapshot, and PNG screenshot writers.
4. Verify the new project through the repo harness commands.

## Concrete Steps

1. Add the project file and minimal app/test folder structure under `Calendar Busy Sync/`.
2. Add `HarnessLaunchOptions`, snapshot models, accessibility IDs, and shared scenario/domain code.
3. Add `AppModel` plus a simple dashboard view that loads the fixture and emits artifacts.
4. Add focused unit and integration tests plus a minimal UI launch test.
5. Run the repo scripts and update this plan with the validation results.

## Validation and Acceptance

- `./scripts/bootstrap-apple`
- `./scripts/build --platform all`
- `./scripts/test-unit`
- `./scripts/test-integration`
- `./scripts/test-ui-macos --smoke`
- `./scripts/test-ui-ios --device both --smoke`

Acceptance means the project builds, the named integration test passes, and both macOS and iOS smoke scripts capture `state.json`, `perf.json`, and `window.png` from the real app.

## Idempotence and Recovery

All work is additive. If a target configuration is wrong, it can be corrected by editing the Xcode project and source files without data migration.

## Artifacts and Notes

- runtime artifacts continue to live under `artifacts/`
- the first version can use synthetic screenshots and scenario-backed data as long as it satisfies the current harness contract

## Interfaces and Dependencies

- depends on Xcode 26 and Swift 6 toolchains already installed locally
- depends on the canned JSON under `Fixtures/scenarios/`
- intentionally does not depend on provider SDKs or network calls yet
