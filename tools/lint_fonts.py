#!/usr/bin/env python3
"""
Font Size Linter
Scans config files for font-family / font-size declarations
and reports inconsistencies.

Supports:
- CSS (font-size, font)
- INI-like (font=Inter:size=11)
- Conf-style (font_size, fontsize, size=)
"""

import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home()

EXTENSIONS = {".css", ".conf", ".ini", ".scss", ".rasi", ".txt"}

PATTERNS = [
    # CSS
    re.compile(r"font-size\s*:\s*([\d.]+)(px|pt|em|rem)", re.I),
    re.compile(r"font\s*:\s*.*?([\d.]+)(px|pt)", re.I),

    # ini / conf
    re.compile(r"font\s*=\s*.*?size\s*=\s*([\d.]+)", re.I),
    re.compile(r"font[_\-]?size\s*=\s*([\d.]+)", re.I),

    # loose size assignments
    re.compile(r"\bsize\s*=\s*([\d.]+)\b"),
]

def scan_file(path: Path):
    results = []
    try:
        text = path.read_text(errors="ignore")
    except Exception:
        return results

    for i, line in enumerate(text.splitlines(), 1):
        for pat in PATTERNS:
            m = pat.search(line)
            if m:
                size = m.group(1)
                unit = m.group(2) if len(m.groups()) > 1 else ""
                results.append((path, i, size, unit.strip()))
    return results

def main():
    findings = []

    for path in ROOT.rglob("*"):
        if path.suffix.lower() in EXTENSIONS and path.is_file():
            findings.extend(scan_file(path))

    if not findings:
        print("✓ No font size declarations found.")
        return

    print("\nFONT SIZE FINDINGS\n" + "-" * 72)
    for path, line, size, unit in sorted(findings, key=lambda x: float(x[2])):
        print(f"{path}:{line:<4} → size = {size}{unit}")

    print("\nSUMMARY\n" + "-" * 72)
    sizes = sorted({float(f[2]) for f in findings})
    print("Unique sizes detected:", ", ".join(str(s) for s in sizes))

if __name__ == "__main__":
    main()
