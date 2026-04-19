# RELIABILITY.md

This document defines current reliability expectations.

## Reliability goals

- a user-selected calendar set should converge to the same mirrored busy view after retries, relaunches, and background resumes
- duplicate mirror writes should be avoided through deterministic identity and idempotent reconciliation
- harness commands should fail clearly when required Xcode or simulator prerequisites are missing

## Active service expectations

### Startup

- `./scripts/bootstrap-apple` must report the resolved Xcode project path, scheme, fixture root, and available simulator IDs
- `./scripts/build --platform all` must either build or fail with a concrete prerequisite message

### Sync correctness

- a source event marked anything other than `free` / `available` must plan a mirrored busy slot for every other selected destination calendar
- a source event marked `free` / `available` must not create a mirrored busy slot
- mirror reconciliation must update or delete previously written holds when source events change or disappear

## Required telemetry

Do not capture in logs:

- full provider access tokens
- real attendee lists
- event descriptions or conferencing URLs from source calendars

Capture enough structured state to answer:

- which accounts and calendars are connected
- which calendars are selected as sync participants
- how many mirror candidates were planned, written, skipped, retried, or failed
- whether the current snapshot was generated from a canned harness scenario or a live provider session

## Retry policy

- provider adapters may retry transient provider failures with bounded backoff
- non-retriable auth or permission failures must surface clearly to the user
- mirror writes should be idempotent so retried requests do not create duplicate busy slots

## Startup and smoke checks

- bootstrap: `./scripts/bootstrap-apple`
- build: `./scripts/build --platform all`
- unit tests: `./scripts/test-unit`
- integration tests: `./scripts/test-integration`
- macOS smoke: `./scripts/test-ui-macos --smoke`
- iOS smoke: `./scripts/test-ui-ios --device both --smoke`
- docs verification: `python3 scripts/knowledge/check_docs.py`
- ExecPlan verification: `python3 scripts/check_execplan.py`

## Incident learning loop

After a material incident:

- add or update a regression test or harness scenario
- update this file if the failure exposed a missing invariant
- update `docs/QUALITY_SCORE.md` if the issue reflects structural debt
