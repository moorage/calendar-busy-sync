# QUALITY_SCORE.md

Purpose: make structural quality legible, track debt, and support small clean-up PRs.

Scoring scale:

- 5 = strong
- 4 = solid with minor gaps
- 3 = acceptable but notable debt
- 2 = fragile
- 1 = high risk / poor legibility

Last refreshed: 2026-04-18
Refresh owner: knowledge automation + reviewer of affected PRs

## Scorecard

- Architecture legibility: 3
- Boundary parsing / type discipline: 2
- Test strength: 1
- Reliability / observability: 2
- Security hardening: 2
- Documentation freshness: 4
- Operational simplicity: 3

## Evidence

- the control-plane docs now describe the intended Apple-platform sync architecture and harness contracts
- reusable Xcode wrapper scripts exist, but the app targets they expect have not been created yet
- no Swift implementation, test suite, or provider adapters are checked in yet

## Structural debt register

- the Xcode project and Swift targets do not exist yet
- harness launch arguments and state snapshots are specified but not implemented in app code
- provider adapters, sync rules, and reconciliation logic are still only documented

## Improvement rules

- raise scores only when code, tests, and docs all justify it
- treat harness scripts as helpful scaffolding, not proof of app correctness

## Maintenance rule

Do not manually inflate scores.
Adjust them only when the code, tests, or docs materially justify it.
