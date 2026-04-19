# Ideation Area

`docs/ideas/` is the pre-implementation space for this repository.

Use it to capture work that is worth shaping, discussing, or prioritizing, but is not yet being implemented. This area is intentionally upstream of `docs/exec-plans/`: idea briefs hold context and tradeoffs, while ExecPlans hold committed execution details.

## What belongs here

- candidate product, platform, harness, or reliability work that should not live as tribal knowledge
- fuller idea briefs that explain the problem, proposed direction, non-goals, and open questions
- prioritization signals that help decide what should become an ExecPlan next

## What does not belong here

- active implementation plans with milestones and verification history
- user-visible requirements that are already true today; those belong in `docs/product-specs/`
- architecture facts that are already true today; those belong in `ARCHITECTURE.md`

## Workflow

1. Add or update the row in `docs/ideas/index.md`. Treat that file as the authoritative backlog view.
2. If the idea needs more than a sentence, create or update a document under `docs/ideas/backlog/`.
3. Set both a `Status` and a `Priority lane`.
4. Keep the brief focused on intent, tradeoffs, and readiness. Do not turn it into an implementation plan.
5. Promote the idea into `docs/exec-plans/active/` only when implementation is accepted and the work needs milestones, commands, and progress tracking.

## Status values

- `seed` — captured in the backlog, but still too raw for deeper planning
- `shaping` — a brief exists and the problem is framed, but open questions still matter
- `ready-to-plan` — the brief is stable enough to turn into an ExecPlan when capacity exists
- `parked` — intentionally retained, but not being actively prioritized
- `promoted` — an ExecPlan now owns implementation; keep the idea brief only as upstream context

## Priority lanes

- `now` — strong candidate for the next implementation cycle; blocking risk, strategy, or important operator value
- `next` — valuable soon, but not the immediate best use of implementation time
- `later` — worth preserving and revisiting, but not near-term
- `parked` — keep for memory and context, not for active planning

Within the same lane, rank ideas by the combination of `Impact`, `Confidence`, and `Effort`:

- higher impact beats lower impact
- higher confidence beats lower confidence when impact is similar
- smaller effort beats larger effort when impact and confidence are similar

Do not pretend this is exact scoring. The goal is legible prioritization, not fake precision.

## Idea brief requirements

Every document in `docs/ideas/backlog/` should include:

- `## Snapshot`
- `## Why this matters`
- `## Current evidence`
- `## Proposed direction`
- `## Non-goals`
- `## Priority and sequencing`
- `## Open questions`
- `## Promotion trigger`

The `## Snapshot` section should include at least:

- `Status`
- `Priority lane`
- `Impact`
- `Confidence`
- `Effort`
- `Last reviewed`

Use `docs/ideas/templates/idea-template.md` when creating a new idea brief.
