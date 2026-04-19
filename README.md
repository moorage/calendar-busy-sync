# Calendar Busy Sync

Universal Apple-platform calendar busy-sync app for macOS, iPhone, and iPad.

The repository is being bootstrapped from control-plane docs and harness scripts into a native calendar-sync shell. The durable workflow lives in the files below:

- `AGENTS.md`
- `ARCHITECTURE.md`
- `.agents/PLANS.md`
- `docs/PLANS.md`
- `docs/product-specs/calendar-sync.md`
- `docs/harness.md`
- `docs/debug-contracts.md`

## Product summary

The app lets one person connect multiple calendar accounts, choose exactly which calendars in each account participate, and mirror any event that is not `free` / `available` into all other selected calendars as busy hold blocks. The goal is to prevent double-booking across multiple jobs, gigs, and companies without exposing full event details between accounts.

## Quickstart

Prerequisites:

- full Xcode installed
- `xcodebuild`, `swift`, and `python3` available in Terminal
- iPhone and iPad simulators installed if you want simulator smoke coverage

Bootstrap and inspect the environment:

```bash
./scripts/bootstrap-apple
```

Build the app:

```bash
./scripts/build --platform all
```

Run narrow validation:

```bash
./scripts/test-unit
./scripts/test-ui-macos --smoke
./scripts/test-ui-ios --device iphone --smoke
./scripts/test-ui-ios --device ipad --smoke
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
- `artifacts/` is runtime-only and ignored by git
