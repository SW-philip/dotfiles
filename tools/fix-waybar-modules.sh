#!/usr/bin/env python3
import os
import re
import glob

files_to_fix = [
    "battery.nix", "cpu_temp.nix", "idle-inhibit.nix",
    "powerprofile.nix", "volume.nix", "bluetooth.nix",
    "dnd.nix", "netstatus.nix"
]

base_path = os.path.expanduser("~/nixos/home/waybar")

for filename in files_to_fix:
    filepath = os.path.join(base_path, filename)
    if not os.path.exists(filepath):
        continue

    with open(filepath, 'r') as f:
        lines = f.readlines()

    new_lines = []
    in_options_block = False
    skip_next_enable = False
    module_name = filename.replace(".nix", "")

    # Find the description string first
    desc_match = None
    for line in lines:
        m = re.search(r'lib\.mkEnableOption\s+"([^"]+)"', line)
        if m:
            desc_match = m.group(1)
            break

    if not desc_match:
        print(f"Skipping {filename}: No description found.")
        continue

    # Reconstruct the file
    found_enable = False
    for i, line in enumerate(lines):
        stripped = line.strip()

        # Skip the broken line if it exists
        if re.match(r'^(options\.waybar\.[a-z_]+\.enable\s*=|lib\.mkEnableOption)', stripped):
            if not found_enable:
                # We are replacing this line with the proper structure
                # Insert options block BEFORE the config block starts
                # We need to detect if we are about to enter config or if we are at the top level

                # Check if next non-empty line is 'config' or '{'
                # For safety, we inject the options block immediately after the opening brace of the module
                pass

        # Logic to inject the correct structure
        # We assume the file starts with: { config, lib, pkgs, ... }: {
        # We need to insert 'options = { ... };' and 'config = {'

        if not found_enable and re.match(r'^\s*$', line):
            # Empty line, maybe we are ready to inject?
            pass

        # Heuristic: If we see the broken line, we replace it and inject structure
        if re.match(r'^(options\.waybar\.[a-z_]+\.enable\s*=|lib\.mkEnableOption)', stripped):
            found_enable = True
            # Inject the correct structure here
            # We need to know if we are inside the main attribute set
            # Let's just replace the whole file content with a template if it's simple

            # Better approach: Just rewrite the file entirely if it matches the pattern
            # Read the whole file, find the enable line, and split into 'before' and 'after'

            # Let's restart the loop logic for this specific file
            break

    # Simpler approach: Rewrite the file completely if it matches the known bad pattern
    content = "".join(lines)

    # Check if it has the bad pattern
    if re.search(r'options\.waybar\.[a-z_]+\.enable\s*=', content) or re.search(r'^\s*lib\.mkEnableOption', content, re.MULTILINE):
        # Extract the description
        desc = desc_match

        # Extract the rest of the file (everything after the enable line)
        # We need to find the line number of the enable line
        enable_line_idx = -1
        for idx, line in enumerate(lines):
            if re.search(r'(options\.waybar\.[a-z_]+\.enable\s*=|lib\.mkEnableOption)', line):
                enable_line_idx = idx
                break

        if enable_line_idx != -1:
            # Get the rest of the file (config logic)
            rest_of_file = "".join(lines[enable_line_idx+1:])

            # Create the new file
            new_content = f"""{{ config, lib, pkgs, ... }}:
{{
  options = {{
    waybar.{module_name}.enable = lib.mkEnableOption "{desc}";
  }};

  config = {{
{rest_of_file}
  }};
}}
"""
            with open(filepath, 'w') as f:
                f.write(new_content)
            print(f"Fixed: {filename}")
        else:
            print(f"Could not locate enable line in {filename}")
    else:
        print(f"Skipped {filename}: Already looks okay or pattern not found.")

print("Done.")
