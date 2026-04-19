# Implementation Loop

Use this file as the execution runbook once an ExecPlan exists.
If the work is still exploratory and no ExecPlan exists yet, use `docs/ideas/` first; this loop starts when the work has crossed into execution.

## Execution rules

1. Treat the active ExecPlan as the source of truth.
2. Work one milestone at a time.
3. Keep diffs scoped to the current milestone when practical.
4. Run the milestone's narrow validation commands before moving to broader verification.
5. If validation fails, fix the issue before starting the next milestone.
6. Update the ExecPlan `Progress`, `Decision Log`, and `Surprises & Discoveries` after each meaningful stop.
7. Update `.agents/DOCUMENTATION.md` with what changed, what was verified, and what remains.
8. Prefer additive, reversible changes when risk is high.
9. If the plan changes materially, update the plan before or while changing the code, not after.

## Useful loop

1. Read the current milestone.
2. Inspect the relevant code paths and docs.
3. Implement the smallest coherent slice.
4. Run narrow validation first.
5. Run broader verification if the slice passes.
6. Update the plan and `.agents/DOCUMENTATION.md`.
7. Continue or stop with the repo in a coherent state.
