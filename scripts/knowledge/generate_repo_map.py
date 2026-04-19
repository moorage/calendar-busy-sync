#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "generated" / "repo-map.json"

NAME_IGNORE = {
    ".git",
    ".next",
    ".venv",
    "__pycache__",
    "build",
    "coverage",
    "dist",
    "node_modules",
}

PATH_PREFIX_IGNORE = {
    "artifacts",
    "tmp",
}

def repo_name() -> str:
    package_path = ROOT / "package.json"
    if package_path.exists():
        try:
            package = json.loads(package_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            package = {}
        name = str(package.get("name", "")).strip()
        if name:
            return name
    return ROOT.name

def should_ignore(path: Path) -> bool:
    rel = path.relative_to(ROOT)
    if path.name in NAME_IGNORE:
        return True
    if path.name.endswith(".pyc"):
        return True
    rel_str = rel.as_posix()
    if any(rel_str == prefix or rel_str.startswith(f"{prefix}/") for prefix in PATH_PREFIX_IGNORE):
        return True
    return False

def walk(path: Path):
    items = []
    for child in sorted(path.iterdir(), key=lambda p: p.name):
        if should_ignore(child):
            continue
        if child.is_dir():
            items.append({
                "type": "dir",
                "name": child.name,
                "children": walk(child),
            })
        else:
            items.append({
                "type": "file",
                "name": child.name,
            })
    return items

data = {
    "root": repo_name(),
    "tree": walk(ROOT),
}

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print(f"Wrote {OUT}")
