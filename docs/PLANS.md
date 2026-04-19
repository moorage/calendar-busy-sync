# ExecPlan Location Guide

This repository is in bootstrap mode. The durable Codex control plane described by the Apple harness now exists, and `.agents/PLANS.md` is the authoritative ExecPlan standard. This file is the routing guide for where plans live and how they move.

## Source of truth

- authoritative standard: `.agents/PLANS.md`
- active plans: `docs/exec-plans/active/`
- completed plans: `docs/exec-plans/completed/`

## Naming

Use `YYYY-MM-DD-short-kebab-name.md`.

New work should keep one active plan per major workstream.

## Working rules

- keep `Progress`, `Decision Log`, `Surprises & Discoveries`, and `Outcomes & Retrospective` current
- update the active plan before implementation diverges from it
- move finished plans into `docs/exec-plans/completed/`
- run `python3 scripts/check_execplan.py` whenever an active plan changes
