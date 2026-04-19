#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IDEAS_DIR = ROOT / "docs" / "ideas"
README_PATH = IDEAS_DIR / "README.md"
INDEX_PATH = IDEAS_DIR / "index.md"
TEMPLATE_PATH = IDEAS_DIR / "templates" / "idea-template.md"
BACKLOG_DIR = IDEAS_DIR / "backlog"

REQUIRED_README_HEADINGS = [
    "What belongs here",
    "What does not belong here",
    "Workflow",
    "Status values",
    "Priority lanes",
    "Idea brief requirements",
]

REQUIRED_INDEX_HEADINGS = [
    "Workflow",
    "Priority lanes",
    "Backlog",
]

REQUIRED_IDEA_HEADINGS = [
    "Snapshot",
    "Why this matters",
    "Current evidence",
    "Proposed direction",
    "Non-goals",
    "Priority and sequencing",
    "Open questions",
    "Promotion trigger",
]

REQUIRED_SNAPSHOT_LABELS = [
    "Status:",
    "Priority lane:",
    "Impact:",
    "Confidence:",
    "Effort:",
    "Last reviewed:",
]


def fail(msg: str) -> None:
    print(f"ERROR: {msg}")
    sys.exit(1)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def find_missing_sections(text: str, headings: list[str]) -> list[str]:
    missing: list[str] = []
    for heading in headings:
        pattern = rf"^##\s+{re.escape(heading)}\s*$"
        if not re.search(pattern, text, re.MULTILINE):
            missing.append(heading)
    return missing


def validate_headings(path: Path, headings: list[str]) -> None:
    missing = find_missing_sections(read_text(path), headings)
    if missing:
        fail(
            f"{path.relative_to(ROOT)} is missing required sections: "
            + ", ".join(missing)
        )


def iter_idea_docs() -> list[Path]:
    if not BACKLOG_DIR.exists():
        return []
    return sorted(path for path in BACKLOG_DIR.rglob("*.md") if path.is_file())


def validate_idea_doc(path: Path, index_text: str) -> None:
    text = read_text(path)
    missing = find_missing_sections(text, REQUIRED_IDEA_HEADINGS)
    if missing:
        fail(
            f"{path.relative_to(ROOT)} is missing required sections: "
            + ", ".join(missing)
        )
    for label in REQUIRED_SNAPSHOT_LABELS:
        if label not in text:
            fail(f"{path.relative_to(ROOT)} is missing snapshot field: {label}")
    rel = path.relative_to(ROOT).as_posix()
    if rel not in index_text:
        fail(f"{rel} is not referenced from docs/ideas/index.md")


def main() -> int:
    for path in [README_PATH, INDEX_PATH, TEMPLATE_PATH]:
        if not path.exists():
            fail(f"Missing required ideation file: {path.relative_to(ROOT)}")
    if not BACKLOG_DIR.exists():
        fail("Missing required ideation directory: docs/ideas/backlog")

    validate_headings(README_PATH, REQUIRED_README_HEADINGS)
    validate_headings(INDEX_PATH, REQUIRED_INDEX_HEADINGS)
    validate_headings(TEMPLATE_PATH, REQUIRED_IDEA_HEADINGS)

    template_text = read_text(TEMPLATE_PATH)
    for label in REQUIRED_SNAPSHOT_LABELS:
        if label not in template_text:
            fail(f"{TEMPLATE_PATH.relative_to(ROOT)} is missing snapshot field: {label}")

    index_text = read_text(INDEX_PATH)
    idea_docs = iter_idea_docs()
    for idea_doc in idea_docs:
        validate_idea_doc(idea_doc, index_text)

    print("Ideation verification passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
