---
name: expert-roundtable
description: >
  Use before decomposition for non-trivial product, workflow, or agentic feature
  requests. Select a small relevant panel of experts, surface the main tensions,
  and produce a concise synthesis memo that shapes the ExecPlan.
---

Use this skill when a request benefits from multiple expert lenses.

Good fits:
- user-facing feature work
- messaging, permissions, or trust-sensitive workflows
- agentic features involving model behavior, prompts, or evals
- architecture changes with operational consequences

Do not use it for:
- trivial bug fixes
- narrow mechanical edits

## Goal

Improve the framing of the request before planning begins.

The output is a concise synthesis, not a long roleplay transcript.

## Typical expert panel for this repo

- Security researcher
- UX expert
- Staff engineer or architect
- Reliability or operations engineer
- Applied ML or evals expert when prompts, routing, or model behavior matter

## Output format

Produce a concise memo with these sections:

### Expert panel
- [expert] — [why selected]

### What problem are we actually solving?
[short reframing]

### Roundtable highlights
- [expert]: [main concern + best recommendation]

### Key tensions
- [tension]

### Synthesis for decomposition
- goals that should drive the plan
- constraints that must shape the plan
- major risks or unknowns
- sequencing implications that must appear in the ExecPlan
