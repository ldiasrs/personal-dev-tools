#!/bin/bash

# -----------------------------------------------------------------------------
# Converts every *.html file in a folder (recursively, including subfolders)
# to Markdown (with frontmatter).
# Output goes into a "markdown-files" subfolder created inside that folder,
# mirroring the original subfolder structure.
# See html-to-md.HOWTO.md for usage details.
# -----------------------------------------------------------------------------

generate_md() {
    local html_file="$1"
    local out_file="$2"
    local f_name f_basename f_create f_modified

    if [ ! -r "$html_file" ]; then
        echo "     *** file not readable: $html_file"
        return 1
    fi

    f_name=$(basename "$html_file")
    f_basename="${f_name%.*}"

    # macOS (BSD) stat: %SB = birth/creation time, %Sm = modification time
    f_create=$(stat -f "%SB" -t "%Y-%m-%d %H:%M:%S" "$html_file")
    f_modified=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$html_file")

    echo "     Processing $html_file ..."

    mkdir -p "$(dirname "$out_file")"

    {
        echo "---"
        echo "title:"
        echo "  - $f_basename"
        echo "created: $f_create"
        echo "updated: $f_modified"
        echo "tags:"
        echo "  - medium"
        echo "---"
        html2markdown --input "$html_file"
    } > "$out_file"

    echo "     .. $out_file created."
}

# =============================================================================
# MAIN
# =============================================================================
if [ $# -eq 0 ]; then
    echo "usage: $(basename "$0") <folder containing .html files>"
    exit 1
fi

src_dir="${1%/}"

if [ ! -d "$src_dir" ]; then
    echo "     *** not a folder: $src_dir"
    exit 1
fi

out_dir="$src_dir/markdown-files"
mkdir -p "$out_dir"

html_files=()
while IFS= read -r -d '' f; do
    html_files+=("$f")
done < <(find "$src_dir" -path "$out_dir" -prune -o -type f -iname "*.html" -print0)

if [ ${#html_files[@]} -eq 0 ]; then
    echo "     *** no .html files found in $src_dir (searched recursively)"
    exit 1
fi

for f in "${html_files[@]}"; do
    rel_path="${f#"$src_dir"/}"
    out_file="$out_dir/${rel_path%.*}.md"
    generate_md "$f" "$out_file"
done

echo "Done! Converted ${#html_files[@]} file(s) into $out_dir"
