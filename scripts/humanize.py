import os
import re

# Target files in your NixOS repo
EXTENSIONS = ('.nix', '.sh', '.json')

def clean_content(content, filename):
    # 1. Protect Shebangs: If line 1 starts with #!, skip it
    lines = content.splitlines()
    if lines and lines[0].startswith('#!'):
        processed_lines = [lines[0]]
        body = "\n".join(lines[1:])
    else:
        processed_lines = []
        body = content

    # 2. Regex for non-hex, non-interpolation comments
    # This ignores: #ffffff (hex) and ${...} (nix interpolation)
    comment_pattern = r'(?m)(?<!\S)#(?![0-9a-fA-F]{3,6}\b)(?![^{]*\}).*$'

    # Remove single-line comments
    body = re.sub(comment_pattern, '', body)

    # 3. Remove C-style multi-line comments /* ... */
    body = re.sub(r'/\*.*?\*/', '', body, flags=re.DOTALL)

    # 4. Final Cleanup: Remove trailing whitespace and excessive empty lines
    cleaned = body.strip()
    return "\n".join(processed_lines + [cleaned]) if processed_lines else cleaned

def run_cleanup(target_dir):
    for root, _, files in os.walk(target_dir):
        for file in files:
            if file.endswith(EXTENSIONS):
                path = os.path.join(root, file)
                print(f"Humanizing: {path}")

                with open(path, 'r') as f:
                    content = f.read()

                new_content = clean_content(content, file)

                with open(path, 'w') as f:
                    f.write(new_content)

if __name__ == "__main__":
    run_cleanup(".")
