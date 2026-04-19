---
name: feature-critic
description: >
  Use after an ExecPlan exists and before implementation starts. Critique the plan
  from failure-oriented lenses such as security, UX, reliability, privacy, abuse,
  and eval coverage, then produce the minimum set of plan changes needed before coding.
---

Use this skill after an ExecPlan has been drafted for non-trivial feature work.

Good fits:
- user-facing product features
- agent or tool-calling workflows
- work involving auth, messaging, integrations, or sensitive data
- plans with staged rollout, monitoring, or rollback requirements

## Goal

Stress-test the ExecPlan before implementation starts.

The output is a concise critique memo, not a rewrite of the whole plan.

## Required workflow

1. Read the current ExecPlan and relevant repo guidance.
2. Restate the feature and implementation intent in one short paragraph.
3. Select 3 to 5 critics and explain why each matters.
4. For each critic, identify:
   - the fragile assumption
   - the missing risk or validation
   - the required ExecPlan change
5. Prioritize findings into:
   - must fix before implementation
   - should fix if low-cost
   - monitor during implementation
