# Ideation Index

`docs/ideas/index.md` is the authoritative backlog for work that is being explored, shaped, or queued, but not yet implemented.

Every document under `docs/ideas/backlog/` must appear here.

## Workflow

1. Add new ideas here first, even if they begin as a one-line seed.
2. Expand any idea that needs more context into `docs/ideas/backlog/<slug>.md`.
3. Keep the table sorted by `Priority lane`, then by how ready the idea is to promote.
4. Move implementation detail into an ExecPlan only when the work is actually being started.

## Priority lanes

- `now` - best candidate for the next implementation cycle
- `next` - important, but not first
- `later` - valuable to preserve, not near-term
- `parked` - intentionally held without active planning pressure

## Backlog

| Priority lane | Status | Impact | Confidence | Effort | Idea | Why now | Doc |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `now` | `ready-to-plan` | `high` | `medium` | `high` | Busy-slot mirroring core | The repository now has a harness, but the actual cross-account sync slice still needs its first implementation plan. | `docs/ideas/backlog/busy-slot-mirroring-core.md` |
