---
name: create-exec-plan
description: Create or update a living ExecPlan under docs/exec-plans/active/ for any feature, migration, investigation, or refactor that spans multiple files or requires design choices.
---

Read in order:
1. `AGENTS.md`
2. `ARCHITECTURE.md`
3. `docs/PLANS.md`
4. `.agents/IMPLEMENT.md`
5. relevant `docs/product-specs/*`
6. relevant `docs/ideas/backlog/*` brief if the work is being promoted from ideation
7. nearest nested `AGENTS.md` if any

For complex, ambiguous, or risky work, prefer this flow:
1. start with native Codex `/plan` mode
2. if the work is feature-shaped or trust-sensitive, use `expert-roundtable`
3. use `execplan-decompose`
4. draft or update one ExecPlan in `docs/exec-plans/active/`
5. if an ExecPlan already exists, update it instead of creating a duplicate
6. before implementation, use `feature-critic` and fold material findings back into the plan

Output:
- create or update one file under `docs/exec-plans/active/`

Requirements:
- include all required sections from `docs/PLANS.md`
- include exact file paths
- include exact verification commands
- include explicit assumptions
- carry forward the rationale, priority, and promotion trigger from an existing `docs/ideas/backlog/*` brief when one exists
- include rollout/rollback or recovery guidance when relevant
- include screencast steps for any new feature or material user-visible workflow change
- update `Progress`, `Surprises & Discoveries`, and `Decision Log` as work proceeds

Do not:
- ask the user for “next steps” when the plan already implies them
- leave the plan without current progress after meaningful work
- create planning theater; optimize for an executable artifact
