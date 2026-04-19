---
name: execplan-decompose
description: >
  Use after initial framing and before creating or revising an ExecPlan for
  complex work. Break the task into dependency-aware milestones, rollout/rollback
  notes, validation, and integration points so the resulting ExecPlan is executable.
---

Use this skill only when creating or improving an ExecPlan for work with real sequencing constraints, migration risk, or nontrivial validation requirements.

Do not use this skill for:
- simple bug fixes
- small isolated edits
- straightforward tasks with no real sequencing constraints

## Goal

Improve the quality of the final ExecPlan by doing a compact decomposition first.

The decomposition is a means, not the output.
The output should be a better ExecPlan in this repository's expected format.

## Required workflow

1. Read `AGENTS.md`, `ARCHITECTURE.md`, and `docs/PLANS.md` first.
2. Carry forward:
   - hard constraints
   - major risks and unknowns
   - sequencing implications
   - validation requirements
3. Identify the task structure:
   - prerequisite or foundation work
   - branches that can proceed independently
   - integration or synthesis points
   - validation, observability, rollout, and rollback work
4. Convert that structure into the ExecPlan:
   - milestones in dependency order
   - explicit assumptions and unknowns
   - concrete verification commands
   - recovery or rollback notes when relevant
5. Prefer repository-specific grounding over abstract planning language.
6. If uncertainty remains, encode it as an investigation milestone rather than pretending it is resolved.
