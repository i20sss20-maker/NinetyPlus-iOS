#!/usr/bin/env python3
"""Fail release CI on high-risk or accidentally shipped development leftovers."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources"
files = sorted(SOURCE.rglob("*.swift"))
text_by_file = {p: p.read_text(encoding="utf-8") for p in files}

checks = [
    ("forced try", re.compile(r"\btry!")),
    ("forced cast", re.compile(r"\bas!\s")),
    ("fatalError", re.compile(r"\bfatalError\s*\(")),
    ("preconditionFailure", re.compile(r"\bpreconditionFailure\s*\(")),
    ("assertionFailure", re.compile(r"\bassertionFailure\s*\(")),
    ("development marker", re.compile(r"\b(?:TODO|FIXME|HACK)\b")),
    ("debug print", re.compile(r"\bprint\s*\(")),
]

problems = []
for path, text in text_by_file.items():
    for label, pattern in checks:
        for match in pattern.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            problems.append(f"{path.relative_to(ROOT)}:{line}: {label}")

# This file was verified against the exact Build 104 tested source snapshot and had
# no route/reference. Keep it out unless a real product surface intentionally adds it.
dead_view = SOURCE / "Views" / "PlayerCompareView.swift"
if dead_view.exists():
    problems.append("Sources/Views/PlayerCompareView.swift: unused product view was reintroduced")

if problems:
    print("Commercial hygiene audit FAILED")
    for problem in problems:
        print(" -", problem)
    raise SystemExit(1)

lines = sum(text.count("\n") + 1 for text in text_by_file.values())
print(f"PASS: commercial hygiene audit ({len(files)} Swift files, {lines} lines, no blocked patterns)")
