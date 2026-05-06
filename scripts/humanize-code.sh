TARGET_DIR="${1:-.}"

echo "--- Humanizing Repo: Removing all commentary


find "$TARGET_DIR" -type f \( -name "*.nix" -o -name "*.sh" -o -name "*.json" \) | while read -r file; do
    echo "Processing: $file"



    perl -i -pe 's/(^|\s)#(?!([0-9a-fA-F]{3}|[0-9a-fA-F]{6})\b).*//g' "$file"


    perl -i -0777 -pe 's/\/\*.*?\*\///gs' "$file"


    perl -i -pe 's/(^|\s)--.*//g' "$file"


    sed -i 's/[[:space:]]*$//' "$file"
done

echo "Done. The mechanical echoes are gone."