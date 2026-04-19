#!/usr/bin/env python3
from __future__ import annotations
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def changed_files():
    try:
        out = subprocess.check_output(
            ["git", "status", "--porcelain"],
            cwd=ROOT,
            text=True
        )
        changed = []
        for line in out.splitlines():
            if not line:
                continue
            path = line[3:]
            if " -> " in path:
                path = path.split(" -> ", 1)[1]
            changed.append(path.strip())
        return changed
    except Exception:
        return []

files = changed_files()
hints = []

if any(
    "sync" in f.lower()
    or "calendar" in f.lower()
    or "provider" in f.lower()
    for f in files
):
    hints.append("Consider docs/product-specs/calendar-sync.md, docs/RELIABILITY.md, and docs/SECURITY.md updates.")
if any("auth" in f.lower() or "security" in f.lower() or "token" in f.lower() for f in files):
    hints.append("Consider docs/SECURITY.md updates.")
if any(f.startswith("Calendar Busy Sync/") or f.startswith("Fixtures/") for f in files):
    hints.append("Consider ARCHITECTURE.md if boundaries or domain concepts changed.")
if any(
    f.startswith(".codex/")
    or f.startswith(".agents/")
    or f.startswith("scripts/knowledge/")
    or f.startswith("scripts/lib/")
    or f in {
        "scripts/bootstrap-apple",
        "scripts/build",
        "scripts/test-unit",
        "scripts/test-integration",
        "scripts/test-ui-macos",
        "scripts/test-ui-ios",
        "scripts/capture-checkpoint",
        "scripts/agent-loop",
    }
    for f in files
):
    hints.append("Consider README.md, AGENTS.md, docs/PLANS.md, docs/harness.md, docs/debug-contracts.md, and python3 scripts/knowledge/check_docs.py after control-plane changes.")
if any(f.startswith("docs/ideas/") or f == "scripts/check_ideation.py" for f in files):
    hints.append("Keep docs/ideas/index.md authoritative, and run python3 scripts/check_ideation.py after ideation changes.")
if any(f.startswith("scripts/ci/") for f in files):
    hints.append("If the change materially alters a visible workflow, update docs/harness.md with any capture-path changes.")
if not hints:
    hints.append("No obvious doc drift detected by heuristics.")

for hint in dict.fromkeys(hints):
    print(hint)
