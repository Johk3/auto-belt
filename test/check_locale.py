#!/usr/bin/env python3
"""Check runtime translation references against the English locale."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def check(root=ROOT):
    sources = [root / "control.lua", *sorted((root / "scripts").glob("*.lua"))]
    used = set()
    for source in sources:
        used.update(re.findall(r'''["']auto-belt\.([^"']+)["']''', source.read_text()))
    available = set()
    section = None
    for line in (root / "locale/en/auto-belt.cfg").read_text().splitlines():
        line = line.strip()
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
        elif section == "auto-belt" and "=" in line and not line.startswith((";", "#")):
            available.add(line.split("=", 1)[0].strip())
    missing = sorted(used - available)
    unused = sorted(available - used)
    for key in missing:
        print(f"Missing: auto-belt.{key}")
    for key in unused:
        print(f"Warning: unused auto-belt.{key}")
    print(f"Locale check: {len(missing)} missing, {len(unused)} unused")
    return int(bool(missing))


if __name__ == "__main__":
    raise SystemExit(check())
