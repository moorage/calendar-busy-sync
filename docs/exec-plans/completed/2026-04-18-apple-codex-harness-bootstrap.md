# Apple Codex Harness Bootstrap

## Purpose / Big Picture

Replace the generic placeholder repo harness with an Apple-platform control plane tailored to Calendar Busy Sync so future implementation work has the right docs, scripts, and validation entry points.

## Progress

- [x] 2026-04-18T23:18Z review the existing `free-markdown-viewer/` harness and compare it against `calendar-busy-sync/`
- [x] 2026-04-18T23:31Z port and adapt the Apple harness docs, Codex config, and Xcode wrapper scripts
- [x] 2026-04-18T23:38Z verify the plan, product identity, and docs validators after the harness conversion

## Surprises & Discoveries

- 2026-04-18: `calendar-busy-sync/README.md` was empty and the control docs were mostly generic web-service placeholders, so the safest change was a broad control-plane replacement rather than small edits.
- 2026-04-18: the repo already had an ideation validator, which meant the harness conversion also needed a valid `docs/ideas/backlog/` entry to keep `verify:docs` coherent.

## Decision Log

- 2026-04-18: kept the existing ideation area and knowledge scripts instead of deleting them, because they remain useful for shaping the first real sync implementation.
- 2026-04-18: ported only the reusable Apple bootstrap/build/test harness pieces, not the App Store release automation, because the Xcode project and release identity do not exist yet.

## Outcomes & Retrospective

The repo now behaves like an Apple app harness instead of a mismatched generic scaffold. Remaining work is implementation-oriented: create the Xcode project, add Swift targets, and satisfy the documented harness contracts.

## Context and Orientation

Relevant files:

- `AGENTS.md`
- `README.md`
- `ARCHITECTURE.md`
- `.codex/config.toml`
- `.codex/local-environment.yaml`
- `.agents/PLANS.md`
- `.agents/DOCUMENTATION.md`
- `docs/harness.md`
- `docs/debug-contracts.md`
- `docs/product-specs/calendar-sync.md`
- `scripts/lib/product-identity.sh`
- `scripts/lib/xcode-env.sh`

The source harness reference is `../free-markdown-viewer/`, but this plan captures the adapted state for this repo directly.

## Plan of Work

1. Replace placeholder control-plane docs with Apple-specific, calendar-sync-aware documents.
2. Add the missing ExecPlan standard and active/completed plan directories.
3. Import reusable Xcode wrapper scripts and adapt them to sync-scenario fixtures instead of markdown fixtures.
4. Verify the imported harness with the local validators and repo-map refresh.

## Concrete Steps

1. Rewrite `AGENTS.md`, `README.md`, and `ARCHITECTURE.md` around the calendar-sync product and Apple workflow.
2. Add `.agents/PLANS.md`, `docs/harness.md`, and `docs/debug-contracts.md`.
3. Create scenario-fixture and product-spec scaffolding under `Fixtures/` and `docs/product-specs/`.
4. Add `scripts/lib/product-identity.sh`, `scripts/lib/xcode-env.sh`, and the Apple wrapper scripts.
5. Run the docs and product-identity validators plus knowledge refresh.

## Validation and Acceptance

- `python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-18-apple-codex-harness-bootstrap.md`
- `./scripts/verify-product-identity`
- `python3 scripts/knowledge/check_docs.py`
- `python3 scripts/knowledge/generate_repo_map.py`
- `python3 scripts/knowledge/update_quality_score.py`

Acceptance means the repo contains the Apple harness files, the validators pass, and the docs consistently describe calendar busy-sync behavior instead of placeholder or source-project behavior.

## Idempotence and Recovery

The change is documentation and script scaffolding only. If any imported file proves wrong, it can be corrected in a follow-up edit without data migration.

## Artifacts and Notes

- runtime artifacts continue to live under `artifacts/`
- the Xcode project is still intentionally absent, so build/test wrapper commands will fail clearly until that milestone lands

## Interfaces and Dependencies

- depends on `xcodebuild`, `swift`, and `python3`
- depends on future app support for the launch arguments described in `docs/debug-contracts.md`
- reuses the existing knowledge scripts and ideation validator already present in this repo
