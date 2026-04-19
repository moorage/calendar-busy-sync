# Harness Guide

The harness is the shell-first control plane for this repository.

## Commands

- `./scripts/bootstrap-apple`
- `./scripts/build --platform all`
- `./scripts/test-unit`
- `./scripts/test-integration`
- `./scripts/test-ui-macos --smoke`
- `./scripts/test-ui-ios --device both --smoke`
- `./scripts/capture-checkpoint --scenario basic-cross-busy.json --platform-target macos --checkpoint shell-smoke-macos`
- `./scripts/agent-loop`
- `./scripts/verify-product-identity`

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
- honoring `--ui-test-mode 1` so harness launches avoid live-provider side effects
- honoring `--harness-command-dir <path>` for file-based smoke commands once write reconciliation exists

The scripts are responsible for:

- creating output directories
- passing launch arguments or UI-test environment
- copying scenario fixtures into the simulator container when needed
- waiting for the snapshot files to exist
- surfacing missing prerequisites with concrete failure messages

## Current scope

This harness currently covers local bootstrap, build, unit-test, integration-test, and checkpoint-capture scaffolding.

Release automation, App Store export flows, and provider-backed end-to-end sync verification are intentionally out of scope until the Xcode targets and first sync slice exist.
