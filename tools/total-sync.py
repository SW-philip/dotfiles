nix-shell -p python3 --run python3 << 'EOF'
import os
import re

def get_attrs(filepath):
    attrs = {}
    if not os.path.exists(filepath): return attrs
    with open(filepath, 'r') as f:
        # Matches KEY = "VALUE";
        matches = re.findall(r'([A-Z0-9_]+)\s*=\s*"(.*?)";', f.read())
        for k, v in matches:
            attrs[k] = v
    return attrs

base_path = "themes/Rose-Pine/main/palette-main.nix"
master_attrs = get_attrs(base_path)

# Folders to sync
target_folders = ["themes/Lix", "themes/Rose-Pine"]

for folder in target_folders:
    for root, dirs, files in os.walk(folder):
        for file in files:
            if file.endswith(".nix") and "palette" in file:
                path = os.path.join(root, file)
                if path == base_path: continue

                current_attrs = get_attrs(path)
                missing_keys = set(master_attrs.keys()) - set(current_attrs.keys())

                if missing_keys:
                    print(f"Updating {path} with {len(missing_keys)} missing keys...")
                    with open(path, 'r') as f:
                        content = f.read()

                    # Insert missing keys before the closing brace
                    insertion = ""
                    for key in missing_keys:
                        insertion += f'  {key} = "{master_attrs[key]}";\n'

                    new_content = re.sub(r'\}', insertion + '}', content)
                    with open(path, 'w') as f:
                        f.write(new_content)
EOF
