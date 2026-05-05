import os
import re

base_path = os.path.expanduser("~/nixos/home/waybar")
files_to_fix = [
    "battery.nix", "cpu_temp.nix", "idle-inhibit.nix",
    "powerprofile.nix", "volume.nix", "bluetooth.nix", 
    "dnd.nix", "netstatus.nix", "flake-drift.nix"
]

def sanitize_nix(file_path):
    if not os.path.exists(file_path):
        print(f"Skipping: {file_path} (not found)")
        return

    with open(file_path, 'r') as f:
        content = f.read()

    # 1. Clean up any remaining citation junk or double brackets
    content = re.sub(r'\]+\]', '', content)
    content = re.sub(r'\]+\]', ']', content)

    # 2. Find the actual config block and FIX the ${bar} variable
    # We look for the start of the waybar settings and capture everything to the semicolon
    match = re.search(r'programs\.waybar\.settings\.(.*?)\s*=\s*(\{.*?\});', content, re.DOTALL)
    
    if match:
        # We replace ${bar} or any other variable with 'surfaceTopBar'
        inner_logic = match.group(2)
        inner_config = f"programs.waybar.settings.surfaceTopBar.{match.group(1).split('.')[-1]} = {inner_logic};"
    else:
        inner_config = "# Manual fix required: config block structure not recognized"

    # 3. Determine the module name for the option key
    mod_name = os.path.basename(file_path).replace(".nix", "").replace("-", "_")
    
    # 4. Reconstruct the clean template
    clean_template = f'''{{ config, pkgs, lib, ... }}:

{{
  options.waybar.{mod_name}.enable = lib.mkEnableOption "{mod_name} module";

  config = lib.mkIf config.waybar.{mod_name}.enable {{
    {inner_config}
  }};
}}
'''
    with open(file_path, 'w') as f:
        f.write(clean_template)
    print(f"Fixed and Sanitized: {file_path}")

for nix_file in files_to_fix:
    sanitize_nix(os.path.join(base_path, nix_file))

print("\nDone. Now try: nrs --flake ~/nixos#surface")
