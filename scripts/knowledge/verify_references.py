#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
refs = ROOT / "docs" / "references"

required = [
    "repo-conventions-llms.txt",
    "twilio-whatsapp-llms.txt",
    "llm-triage-llms.txt",
    "evals-llms.txt",
    "voice-orchestration-llms.txt",
    "postgresql-llms.txt",
]

missing = [name for name in required if not (refs / name).exists()]
if missing:
    print("Missing references:", ", ".join(missing))
    sys.exit(1)

print("Reference verification passed.")
