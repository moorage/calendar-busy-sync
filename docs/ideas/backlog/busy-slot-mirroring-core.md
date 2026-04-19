# Busy-Slot Mirroring Core

## Snapshot

- Status: `ready-to-plan`
- Priority lane: `now`
- Impact: `high`
- Confidence: `medium`
- Effort: `high`
- Last reviewed: `2026-04-18`

## Why this matters

The entire product promise depends on taking one busy event from a selected source calendar and mirroring an opaque busy hold into the rest of the user-selected calendars. Without this slice, the app cannot prevent double-booking.

## Current evidence

- the product direction is now captured in `docs/product-specs/calendar-sync.md`
- the Apple harness documents deterministic sync-scenario launches and smoke assertions
- no provider adapters, sync planner, or mirror-write reconciliation code exists yet

## Proposed direction

Start with one provider-backed source of truth, normalize event availability into a typed internal model, let the user choose participating calendars, and generate idempotent busy-hold writes for the selected destinations.

## Non-goals

- syncing descriptive event metadata
- shared team scheduling workflows
- automated conflict resolution beyond blocking time

## Priority and sequencing

This is the next major implementation candidate after harness bootstrap. It should become an ExecPlan once the first provider and local storage approach are chosen.

## Open questions

- should the first implementation target only Google Calendar, or include EventKit calendars too
- what identifier scheme should the app use to reconcile mirrored holds across providers
- what minimum metadata should be stored locally to survive relaunches without privacy drift

## Promotion trigger

Promote this idea into `docs/exec-plans/active/` when the first provider integration and mirror reconciliation approach are accepted for implementation.
