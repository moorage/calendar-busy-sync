#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
from datetime import date
import re

ROOT = Path(__file__).resolve().parents[2]
QUALITY = ROOT / "docs" / "QUALITY_SCORE.md"

text = QUALITY.read_text(encoding="utf-8")
text = re.sub(r"Last refreshed: \d{4}-\d{2}-\d{2}", f"Last refreshed: {date.today().isoformat()}", text)
QUALITY.write_text(text, encoding="utf-8")
print(f"Refreshed timestamp in {QUALITY}")
