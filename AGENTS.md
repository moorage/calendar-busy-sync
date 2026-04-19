# AGENTS.md

Purpose: this repository is optimized for safe, autonomous Codex work on a universal Apple-platform calendar busy-sync app that runs on macOS, iPhone, and iPad.

Start here. Use this file as the durable control plane, then follow the repo-specific docs it points to.

## Repository shape

- `Calendar Busy Sync/` - expected Xcode project, app code, unit tests, and UI tests
- `Fixtures/` - deterministic sync scenarios and expected harness inputs
- `scripts/` - shell wrappers, docs validation, repo-map generation, and capture helpers
- `docs/` - product, architecture, reliability, security, harness, and ExecPlan docs
- `.agents/` - authoritative ExecPlan standard, execution runbook, and implementation notes
- `.codex/` - Codex local environment configuration

## First reads

Before non-trivial work, read in this order:

1. `README.md`
2. `ARCHITECTURE.md`
3. `.agents/PLANS.md`
4. `docs/PLANS.md`
5. `docs/product-specs/calendar-sync.md`
6. `docs/harness.md`
7. `docs/debug-contracts.md`
8. `docs/ideas/README.md` when the work is exploratory
9. the active plan in `docs/exec-plans/active/`

## When an ExecPlan is required

Create or update an ExecPlan in `docs/exec-plans/active/` when any of the following is true:

- work is likely to exceed roughly 30 minutes
- work spans multiple files or modules
- a design choice, migration, rollout, rollback, or artifact regeneration is involved
- there are unknowns to investigate
- a change affects sync correctness, privacy boundaries, background execution, reliability, security, or user-visible flows

Skip an ExecPlan only for trivial typo fixes or tightly local changes with no meaningful sequencing or risk.

## Required workflow

- search before adding
- prefer one meaningful change per loop
- keep diffs scoped to the current milestone
- after each meaningful milestone:
  - run the narrowest relevant tests first
  - run `python3 scripts/check_execplan.py` when an active ExecPlan changes
  - run `python3 scripts/knowledge/check_docs.py` when docs or control-plane files change
  - update the active ExecPlan `Progress`, `Decision Log`, and `Surprises & Discoveries`
  - update `.agents/DOCUMENTATION.md`

## Invariants

- external calendar provider payloads are parsed at the boundary
- sync logic decides from normalized event availability, not provider-specific string matching inside app flows
- only user-selected calendars may receive mirrored busy slots
- mirrored busy slots must never create recursive writes back into their source calendar
- provider credentials and tokens stay out of logs and checked-in fixtures
- artifacts live under `artifacts/` and are not checked in
- scripts should hide project paths with spaces and simulator details from normal workflow

## Commands

- bootstrap: `./scripts/bootstrap-apple`
- build: `./scripts/build --platform all`
- unit tests: `./scripts/test-unit`
- integration tests: `./scripts/test-integration`
- macOS UI smoke: `./scripts/test-ui-macos --smoke`
- iOS/iPad UI smoke: `./scripts/test-ui-ios --device both --smoke`
- fast loop: `./scripts/agent-loop`
- checkpoint capture: `./scripts/capture-checkpoint --scenario basic-cross-busy.json --platform-target macos --checkpoint shell-smoke-macos`
- docs verify: `python3 scripts/knowledge/check_docs.py`
- ExecPlan verify: `python3 scripts/check_execplan.py`
- product identity verify: `./scripts/verify-product-identity`
- repo map refresh: `python3 scripts/knowledge/generate_repo_map.py`

## PR expectations

- include acceptance evidence
- include exact commands run
- include updated docs where applicable
- keep the active ExecPlan current and move it to `docs/exec-plans/completed/` when finished
