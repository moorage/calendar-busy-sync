---
name: update-knowledge-base
description: Update AGENTS, architecture, specs, reliability, security, and quality docs when code changes create documentation drift.
---

Purpose:
Use this after implementing or reviewing a change to keep the repo knowledge base synchronized with real behavior.

Read:
- `AGENTS.md`
- `ARCHITECTURE.md`
- `docs/SECURITY.md`
- `docs/RELIABILITY.md`
- `docs/QUALITY_SCORE.md`
- relevant `docs/product-specs/*`

Workflow:
1. inspect changed files
2. determine whether behavior, architecture, reliability, or security posture changed
3. update the smallest set of docs needed
4. if repeated guidance is emerging, update the nearest `AGENTS.md` or create/update a skill
5. run `python3 scripts/knowledge/check_docs.py`

Output:
- minimal doc diffs that eliminate drift
- if no doc changes are needed, state why in the PR description or plan log

Heuristics:
- user-visible behavior => product spec
- repeated review comment => AGENTS or skill
- boundary/layer change => ARCHITECTURE
- failure-mode / telemetry / smoke-path change => RELIABILITY
- trust-boundary / auth / secret / tool-authority change => SECURITY
- evidence-based score shift => QUALITY_SCORE
