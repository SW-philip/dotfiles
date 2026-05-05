#!/usr/bin/env python3
import os
import json
import yaml
import re
import sys
from pathlib import Path
from collections import defaultdict

# Configuration
THEME_DIR = Path.home() / "nixos" / "themes"
FILE_EXTENSIONS = ['.yaml', '.yml', '.json', '.nix', '.txt']
# Regex to find hex codes (e.g., #RRGGBB, #RRGGBBAA)
HEX_PATTERN = re.compile(r'#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{8})')

def parse_file(filepath):
    """Parses a file and returns a dictionary of {attribute: hex_code}."""
    data = {}
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()

        # Try YAML first
        if filepath.suffix in ['.yaml', '.yml']:
            try:
                parsed = yaml.safe_load(content)
                if isinstance(parsed, dict):
                    return extract_hexes(parsed)
            except yaml.YAMLError:
                pass

        # Try JSON
        if filepath.suffix == '.json':
            try:
                parsed = json.loads(content)
                if isinstance(parsed, dict):
                    return extract_hexes(parsed)
            except json.JSONDecodeError:
                pass

        # Fallback: Scan text for hex codes if specific parsers fail or for .nix/.txt
        # This assumes a flat structure or key-value pairs in text files
        lines = content.split('\n')
        for line in lines:
            # Simple heuristic: look for "key: #hex" or "key = #hex"
            if ':' in line or '=' in line:
                parts = re.split(r'[:=]', line, maxsplit=1)
                if len(parts) == 2:
                    key = parts[0].strip().replace('"', '').replace("'", '')
                    val = parts[1].strip()
                    match = HEX_PATTERN.search(val)
                    if match:
                        data[key] = match.group(0)

        # If no structured data found, just dump all hexes with generic keys (not ideal but safe)
        if not data:
            matches = HEX_PATTERN.findall(content)
            for i, m in enumerate(matches):
                data[f"color_{i+1}"] = f"#{m}"

        return data

    except Exception as e:
        print(f"Error parsing {filepath}: {e}")
        return {}

def extract_hexes(obj, prefix=""):
    """Recursively extracts hex codes from nested dictionaries/lists."""
    result = {}
    if isinstance(obj, dict):
        for k, v in obj.items():
            new_key = f"{prefix}.{k}" if prefix else k
            if isinstance(v, str) and HEX_PATTERN.search(v):
                match = HEX_PATTERN.search(v)
                result[new_key] = match.group(0)
            elif isinstance(v, (dict, list)):
                result.update(extract_hexes(v, new_key))
    elif isinstance(obj, list):
        for i, item in enumerate(obj):
            new_key = f"{prefix}[{i}]"
            if isinstance(item, str) and HEX_PATTERN.search(item):
                match = HEX_PATTERN.search(item)
                result[new_key] = match.group(0)
            elif isinstance(item, (dict, list)):
                result.update(extract_hexes(item, new_key))
    return result

def find_palette_files(directory):
    """Finds all potential palette files in the directory."""
    files = []
    if not directory.exists():
        print(f"Error: Directory {directory} does not exist.")
        sys.exit(1)

    for root, _, filenames in os.walk(directory):
        for filename in filenames:
            if any(filename.endswith(ext) for ext in FILE_EXTENSIONS):
                files.append(Path(root) / filename)
    return files

def sync_themes():
    print(f"Scanning {THEME_DIR} for palette files...")
    files = find_palette_files(THEME_DIR)

    if not files:
        print("No palette files found.")
        return

    theme_data = {}
    all_keys = set()

    # 1. Parse all files
    for f in files:
        data = parse_file(f)
        theme_name = f.relative_to(THEME_DIR)
        theme_data[str(theme_name)] = data
        all_keys.update(data.keys())

    print(f"Found {len(files)} files. Analyzing {len(all_keys)} unique attributes...")

    # 2. Identify missing values
    missing_map = defaultdict(list) # theme -> list of missing keys

    for theme, data in theme_data.items():
        for key in all_keys:
            if key not in data:
                missing_map[theme].append(key)

    # 3. Output Results
    print("\n--- MISSING ATTRIBUTES REPORT ---")
    has_missing = False
    for theme, missing_keys in missing_map.items():
        if missing_keys:
            has_missing = True
            print(f"\nTheme: {theme}")
            print(f"  Missing {len(missing_keys)} attributes:")
            for k in sorted(missing_keys):
                print(f"    - {k}")

    if not has_missing:
        print("\nAll themes are perfectly synchronized! No missing attributes found.")
        return

    # 4. Optional: Auto-fix Strategy
    # To auto-fix, you need to choose a "source" theme to copy from.
    # Uncomment the block below to enable auto-generation of fixed files.

    """
    SOURCE_THEME = None # Set this to a specific theme name string, e.g., "catppuccin-mocha.yaml"
    # Or pick the first one alphabetically if none specified
    if not SOURCE_THEME:
        source_theme = sorted(theme_data.keys())[0]
    else:
        source_theme = SOURCE_THEME

    if source_theme not in theme_data:
        print(f"Warning: Source theme '{source_theme}' not found. Skipping auto-fix.")
    else:
        print(f"\n--- AUTO-FIX STRATEGY ---")
        print(f"Using '{source_theme}' as the reference for missing values.")

        for theme, missing_keys in missing_map.items():
            if theme == source_theme:
                continue

            print(f"Updating {theme}...")
            # In a real scenario, you would read the file, update the dict, and write back.
            # Since parsing formats (Nix/YAML) strictly is hard without specific libraries for Nix,
            # we will output the suggested lines to add.

            print(f"  Additions for {theme}:")
            for key in missing_keys:
                val = theme_data[source_theme].get(key, "#000000") # Fallback if source is also missing
                print(f"    {key}: {val}")
            print("-" * 20)
    """

if __name__ == "__main__":
    # Ensure PyYAML is installed
    try:
        import yaml
    except ImportError:
        print("Error: PyYAML is required. Install it with: pip install pyyaml")
        sys.exit(1)

    sync_themes()
