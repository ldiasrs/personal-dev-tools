#!/bin/bash

# Generic decrypt + extract for any .tar.gz.enc archive produced by:
#   - compress-project.sh
#   - backup-home-configs.sh
#   - backup-vscode.sh
# Or any AES-256-CBC + PBKDF2 (iter 200000) openssl-encrypted tar.gz.
#
# Usage: ./decrypt-archive.sh <file.tar.gz.enc> [--to <dir>] [--decrypt-only]
#   --to <dir>      : extract into this directory (default: current dir)
#   --decrypt-only  : just decrypt to .tar.gz, do NOT extract

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
INPUT=""
DEST_DIR=""
DECRYPT_ONLY=false
while [ $# -gt 0 ]; do
    case "$1" in
        --to)
            DEST_DIR="$2"
            shift 2
            ;;
        --decrypt-only)
            DECRYPT_ONLY=true
            shift
            ;;
        *)
            INPUT="$1"
            shift
            ;;
    esac
done

if [ -z "$INPUT" ]; then
    print_message "Usage: $(basename "$0") <file.tar.gz.enc> [--to <dir>] [--decrypt-only]" "$RED"
    exit 1
fi

if [ ! -f "$INPUT" ]; then
    print_message "Error: file not found: $INPUT" "$RED"
    exit 1
fi

# Resolve absolute paths
INPUT="$(cd "$(dirname "$INPUT")" && pwd)/$(basename "$INPUT")"
INPUT_DIR="$(dirname "$INPUT")"
INPUT_BASE="$(basename "$INPUT")"

# Determine if encrypted
IS_ENCRYPTED=false
case "$INPUT_BASE" in
    *.tar.gz.enc) IS_ENCRYPTED=true ;;
    *.tar.gz)
        if [ "$DECRYPT_ONLY" = true ]; then
            print_message "Error: --decrypt-only used but file is already unencrypted" "$RED"
            exit 1
        fi
        ;;
    *)
        print_message "Error: input must be a .tar.gz or .tar.gz.enc file" "$RED"
        exit 1
        ;;
esac

# Resolve destination
if [ -z "$DEST_DIR" ]; then
    DEST_DIR="$(pwd)"
fi
mkdir -p "$DEST_DIR"
DEST_DIR="$(cd "$DEST_DIR" && pwd)"

# Compute the decrypted filename (strip .enc)
DECRYPTED_NAME="${INPUT_BASE%.enc}"

# Decide where the decrypted intermediate lives
if [ "$DECRYPT_ONLY" = true ]; then
    # Final destination IS the decrypted file
    DECRYPTED_PATH="${DEST_DIR}/${DECRYPTED_NAME}"
else
    # Temp file we'll clean up after extraction
    DECRYPTED_PATH="$(mktemp -t archive-XXXXXX).tar.gz"
fi

trap 'if [ "$DECRYPT_ONLY" = false ] && [ -f "$DECRYPTED_PATH" ]; then rm -f "$DECRYPTED_PATH"; fi' EXIT

# Step 1 — decrypt (if needed)
if [ "$IS_ENCRYPTED" = true ]; then
    if ! command -v openssl >/dev/null 2>&1; then
        print_message "Error: openssl not found (required to decrypt)" "$RED"
        exit 1
    fi

    print_message "🔒 Encrypted archive: $INPUT_BASE" "$BLUE"
    echo -n "Enter password: "
    read_secret PASSWORD
    if [ -z "$PASSWORD" ]; then
        print_message "Empty password. Aborted." "$RED"
        exit 1
    fi

    print_message "Decrypting..." "$YELLOW"
    if ! openssl enc -aes-256-cbc -d -pbkdf2 -iter 200000 \
        -in "$INPUT" -out "$DECRYPTED_PATH" \
        -pass pass:"$PASSWORD" 2>/dev/null; then
        print_message "Error: decryption failed (wrong password?)" "$RED"
        rm -f "$DECRYPTED_PATH"
        exit 1
    fi
    PASSWORD=""

    if [ "$DECRYPT_ONLY" = true ]; then
        SIZE="$(du -h "$DECRYPTED_PATH" | cut -f1)"
        print_message "" "$NC"
        print_message "Done!" "$GREEN"
        print_message "Decrypted file: $DECRYPTED_PATH ($SIZE)" "$GREEN"
        # Don't extract; clear the trap so we don't delete the user's output
        trap - EXIT
        exit 0
    fi
else
    # Already unencrypted — just point at it for extraction
    DECRYPTED_PATH="$INPUT"
    trap - EXIT  # nothing to clean
fi

# Step 2 — peek at contents
print_message "" "$NC"
print_message "Archive contents (first 15 entries):" "$BLUE"
tar -tzf "$DECRYPTED_PATH" 2>/dev/null | head -15 | sed 's/^/  /'
TOTAL_ENTRIES=$(tar -tzf "$DECRYPTED_PATH" 2>/dev/null | wc -l | tr -d ' ')
echo "  ..."
print_message "Total entries: $TOTAL_ENTRIES" "$GRAY"

# Detect archive type heuristically (for friendlier output)
TYPE_LABEL=""
case "$INPUT_BASE" in
    home-configs-*) TYPE_LABEL="home configs backup" ;;
    vscode-backup-*) TYPE_LABEL="VS Code backup" ;;
    *) TYPE_LABEL="archive" ;;
esac

# Step 3 — confirm and extract
print_message "" "$NC"
print_message "Extract $TYPE_LABEL → $DEST_DIR" "$BLUE"
echo -n "Proceed? [y/N] "
read_input CONFIRM
case "$CONFIRM" in
    y|Y|yes) ;;
    *) print_message "Aborted." "$RED"; exit 0 ;;
esac

print_message "Extracting..." "$YELLOW"
if ! tar -xzf "$DECRYPTED_PATH" -C "$DEST_DIR"; then
    print_message "Error: extraction failed" "$RED"
    exit 1
fi

print_message "" "$NC"
print_message "Done!" "$GREEN"
print_message "Extracted to: $DEST_DIR" "$BLUE"

# Type-specific hints
case "$TYPE_LABEL" in
    "home configs backup")
        print_message "Tip: if you extracted into \$HOME, restart your shell or 'source ~/.zshrc'" "$GRAY"
        ;;
    "VS Code backup")
        print_message "Tip: for VS Code backups, prefer ./restore-vscode.sh for extension auto-install" "$GRAY"
        ;;
esac
