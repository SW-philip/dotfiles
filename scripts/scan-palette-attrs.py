#!/usr/bin/env python3
"""
scan-palette-attrs.py (Fixed)
Scans Python scripts for palette dictionary keys (e.g., mapped["BASE"], p['TEXT']).
"""

import argparse
import re
import sys
from pathlib import Path

# Regex to match Python dictionary access: mapped["KEY"] or p['KEY'] or p["KEY"]
PYTHON_KEY_REGEX = re.compile(r'(?:mapped|p)\s*\[\s*["\']([A-Z_][A-Z0-9_]*)["\']\s*\]')

def extract_attrs_from_file(file_path: Path) -> set:
    attrs = set()
    try:
        content = file_path.read_text(errors='ignore')
        matches = PYTHON_KEY_REGEX.findall(content)
        attrs.update(matches)
    except Exception as e:
        print(f"⚠️  Error reading {file_path}: {e}", file=sys.stderr)
    return attrs

def scan_target(target: Path) -> set:
    all_attrs = set()
    if target.is_file():
        if target.suffix == '.py':
            all_attrs.update(extract_attrs_from_file(target))
    elif target.is_dir():
        for file in target.rglob("*.py"):
            if '.git' in str(file) or '__pycache__' in str(file):
                continue
            all_attrs.update(extract_attrs_from_file(file))
    else:
        print(f"❌ Error: {target} is not valid.", file=sys.stderr)
        sys.exit(1)
    return all_attrs

def main():
    parser = argparse.ArgumentParser(description="Scan Python scripts for palette keys.")
    parser.add_argument("target", type=Path, help="Path to script or directory.")
    args = parser.parse_args()

    print(f"🔍 Scanning: {args.target}...")
    attrs = scan_target(args.target)

    if not attrs:
        print("ℹ️  No palette keys found. Did you scan the right file?")
        return

    print(f"\n✅ Found {len(attrs)} unique keys:\n")
    for attr in sorted(attrs):
        print(f"  - {attr}")

    print(f"\n💡 These are the keys your script expects. Ensure 'mapped' in fetch_api_palette includes them.")

if __name__ == "__main__":
    main()
