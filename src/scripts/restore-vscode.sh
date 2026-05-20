#!/bin/bash

# Restore VS Code settings from a backup produced by backup-vscode.sh.
# Auto-detects whether the archive is encrypted (.enc) or not.
#
# Usage: ./restore-vscode.sh <archive.tar.gz[.enc]> [--no-extensions] [--no-backup-existing]
#   --no-extensions      : skip installing extensions
#   --no-backup-existing : don't back up existing settings before overwriting

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m'

print_message() {
    echo -e "${2}${1}${NC}"
}

read_secret() {
    local __var="$1"
    if [ -t 0 ]; then
        read -rs "$__var"
        echo
        return
    fi
    { read -rs "$__var" < /dev/tty; } 2>/dev/null || read -rs "$__var"
    echo
}

read_input() {
    local __var="$1"
    if [ -t 0 ]; then
        read -r "$__var"
        return
    fi
    { read -r "$__var" < /dev/tty; } 2>/dev/null || read -r "$__var"
}

# Parse args
ARCHIVE=""
INSTALL_EXTENSIONS=true
BACKUP_EXISTING=true
for arg in "$@"; do
    case "$arg" in
        --no-extensions) INSTALL_EXTENSIONS=false ;;
        --no-backup-existing) BACKUP_EXISTING=false ;;
        *) ARCHIVE="$arg" ;;
    esac
done

if [ -z "$ARCHIVE" ]; then
    print_message "Usage: $(basename "$0") <archive.tar.gz[.enc]> [--no-extensions] [--no-backup-existing]" "$RED"
    exit 1
fi

if [ ! -f "$ARCHIVE" ]; then
    print_message "Error: archive not found: $ARCHIVE" "$RED"
    exit 1
fi

# Resolve to absolute path
ARCHIVE="$(cd "$(dirname "$ARCHIVE")" && pwd)/$(basename "$ARCHIVE")"

# Detect VS Code paths (macOS)
VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"

# Detect if encrypted
IS_ENCRYPTED=false
case "$ARCHIVE" in
    *.enc) IS_ENCRYPTED=true ;;
esac

# Working area
WORKDIR="$(mktemp -d)"
DECRYPTED_TAR="$WORKDIR/archive.tar.gz"

cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

# Step 1 — decrypt if needed
if [ "$IS_ENCRYPTED" = true ]; then
    if ! command -v openssl >/dev/null 2>&1; then
        print_message "Error: openssl not found (required to decrypt)" "$RED"
        exit 1
    fi
    print_message "🔒 Encrypted archive detected" "$BLUE"
    echo -n "Enter password: "
    read_secret PASSWORD

    if [ -z "$PASSWORD" ]; then
        print_message "Empty password. Aborted." "$RED"
        exit 1
    fi

    print_message "Decrypting..." "$YELLOW"
    if ! openssl enc -aes-256-cbc -d -pbkdf2 -iter 200000 \
        -in "$ARCHIVE" -out "$DECRYPTED_TAR" \
        -pass pass:"$PASSWORD" 2>/dev/null; then
        print_message "Error: decryption failed (wrong password?)" "$RED"
        exit 1
    fi
    PASSWORD=""
else
    cp "$ARCHIVE" "$DECRYPTED_TAR"
fi

# Step 2 — extract
print_message "Extracting..." "$YELLOW"
EXTRACT_DIR="$WORKDIR/extract"
mkdir -p "$EXTRACT_DIR"
if ! tar -xzf "$DECRYPTED_TAR" -C "$EXTRACT_DIR"; then
    print_message "Error: extraction failed" "$RED"
    exit 1
fi

# Find the staged folder inside (e.g. vscode-backup-20260520-130000/)
STAGED=$(find "$EXTRACT_DIR" -maxdepth 1 -mindepth 1 -type d | head -1)
if [ -z "$STAGED" ] || [ ! -d "$STAGED/User" ]; then
    print_message "Error: archive doesn't contain expected 'User/' folder" "$RED"
    exit 1
fi

# Show what we found
print_message "" "$NC"
print_message "Archive contents:" "$BLUE"
[ -f "$STAGED/README.txt" ] && cat "$STAGED/README.txt" | sed 's/^/  /'
echo ""
print_message "User files found:" "$BLUE"
find "$STAGED/User" -maxdepth 1 -mindepth 1 | while read -r f; do
    echo "  • $(basename "$f")"
done

if [ -f "$STAGED/extensions.txt" ]; then
    EXT_COUNT=$(wc -l < "$STAGED/extensions.txt" | tr -d ' ')
    echo "  • extensions.txt ($EXT_COUNT extensions)"
fi

# Confirm
print_message "" "$NC"
print_message "Target: $VSCODE_USER_DIR" "$BLUE"
if [ "$BACKUP_EXISTING" = true ]; then
    print_message "Existing files will be backed up to *.bak.<timestamp>" "$GRAY"
fi
echo -n "Proceed with restore? [y/N] "
read_input CONFIRM
case "$CONFIRM" in
    y|Y|yes) ;;
    *) print_message "Aborted." "$RED"; exit 0 ;;
esac

# Step 3 — copy files into VS Code user dir
mkdir -p "$VSCODE_USER_DIR"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

restore_item() {
    local src="$1"
    local item_name="$(basename "$src")"
    local dest="$VSCODE_USER_DIR/$item_name"

    if [ -e "$dest" ] && [ "$BACKUP_EXISTING" = true ]; then
        mv "$dest" "${dest}.bak.${TIMESTAMP}"
        echo "  ↳ backed up existing $item_name → ${item_name}.bak.${TIMESTAMP}"
    fi
    cp -R "$src" "$dest"
    echo "  ✓ restored $item_name"
}

print_message "" "$NC"
print_message "Restoring User/ files..." "$YELLOW"
for item in "$STAGED/User"/*; do
    [ -e "$item" ] || continue
    restore_item "$item"
done

# Step 4 — install extensions
if [ "$INSTALL_EXTENSIONS" = true ] && [ -f "$STAGED/extensions.txt" ]; then
    if ! command -v code >/dev/null 2>&1; then
        print_message "" "$NC"
        print_message "Warning: 'code' CLI not in PATH — skipping extension install" "$YELLOW"
        print_message "  Install via VS Code: Cmd+Shift+P → 'Shell Command: Install code command in PATH'" "$YELLOW"
        print_message "  Then run: ./restore-vscode.sh $ARCHIVE --no-backup-existing" "$YELLOW"
    else
        print_message "" "$NC"
        print_message "Installing extensions..." "$YELLOW"
        TOTAL=$(wc -l < "$STAGED/extensions.txt" | tr -d ' ')
        INSTALLED=0
        FAILED=0
        SKIPPED=0
        # Build list of already-installed (with versions) for quick skip
        EXISTING_LIST="$WORKDIR/installed.txt"
        code --list-extensions --show-versions > "$EXISTING_LIST" 2>/dev/null

        while IFS= read -r line; do
            [ -z "$line" ] && continue
            # Format: "publisher.id@version"
            EXT_ID="${line%@*}"
            if grep -qiF "$line" "$EXISTING_LIST" 2>/dev/null; then
                echo "  • $EXT_ID (already installed)"
                SKIPPED=$((SKIPPED + 1))
                continue
            fi
            if code --install-extension "$EXT_ID" --force >/dev/null 2>&1; then
                echo "  ✓ $EXT_ID"
                INSTALLED=$((INSTALLED + 1))
            else
                echo -e "  ${RED}✗ $EXT_ID (failed)${NC}"
                FAILED=$((FAILED + 1))
            fi
        done < "$STAGED/extensions.txt"

        print_message "" "$NC"
        print_message "Extensions: $INSTALLED installed, $SKIPPED already present, $FAILED failed (of $TOTAL total)" "$GREEN"
    fi
elif [ "$INSTALL_EXTENSIONS" = false ]; then
    print_message "" "$NC"
    print_message "Skipped extension install (--no-extensions)" "$GRAY"
fi

print_message "" "$NC"
print_message "Done!" "$GREEN"
print_message "Restart VS Code to pick up the new settings." "$BLUE"
