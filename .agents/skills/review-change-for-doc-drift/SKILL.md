---
name: review-change-for-doc-drift
description: Review a proposed or completed change specifically for documentation drift, missing tests, and stale knowledge-base entries.
---

Use when:
- a PR changed multiple modules
- behavior changed without obvious docs updates
- you suspect stale architecture/spec/reliability/security docs

Checklist:
- Does changed behavior still match product specs?
- Did architectural boundaries change?
- Did reliability expectations or smoke commands change?
- Did trust boundaries or risky sinks change?
- Should quality scores shift?
- Should repeated correction become AGENTS or a skill?
- Should a screencast have been added for a new feature or materially changed workflow?

Required output:
- list of required doc updates
- list of optional doc improvements
- list of missing verification evidence
