#!/bin/bash

# Backup VS Code user settings, keybindings, snippets, profiles, MCP config, and the list of installed extensions.
# Produces an (optionally encrypted) tar.gz that can be restored with restore-vscode.sh on a new Mac.
#
# Usage: ./backup-vscode.sh [output-dir] [--no-password]
#   output-dir    : defaults to ~/Documents
#   --no-password : skip encryption (NOT recommended — settings may contain API keys)

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

# Parse args
OUTPUT_DIR=""
USE_PASSWORD=true
for arg in "$@"; do
    case "$arg" in
        --no-password) USE_PASSWORD=false ;;
        *) OUTPUT_DIR="$arg" ;;
    esac
done
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/Documents}"

if [ ! -d "$OUTPUT_DIR" ]; then
    print_message "Error: output dir '$OUTPUT_DIR' does not exist" "$RED"
    exit 1
fi

# VS Code paths (macOS)
VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"
if [ ! -d "$VSCODE_USER_DIR" ]; then
    print_message "Error: VS Code user dir not found at '$VSCODE_USER_DIR'" "$RED"
    print_message "Is VS Code installed?" "$RED"
    exit 1
fi

# Check for 'code' CLI (for extension list)
if ! command -v code >/dev/null 2>&1; then
    print_message "Warning: 'code' CLI not in PATH — extension list will be SKIPPED" "$YELLOW"
    print_message "Install via VS Code: Cmd+Shift+P → 'Shell Command: Install code command in PATH'" "$YELLOW"
    HAS_CODE_CLI=false
else
    HAS_CODE_CLI=true
fi

# Build a staging directory
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
STAGING="$(mktemp -d)"
STAGE_NAME="vscode-backup-${TIMESTAMP}"
STAGE_DIR="${STAGING}/${STAGE_NAME}"
mkdir -p "$STAGE_DIR/User"

# Files to copy from User/ (preserves directory structure)
USER_FILES=(
    "settings.json"
    "keybindings.json"
    "tasks.json"
    "mcp.json"
)

USER_DIRS=(
    "snippets"
    "profiles"
)

print_message "" "$NC"
print_message "Collecting VS Code config from: $VSCODE_USER_DIR" "$BLUE"
print_message "" "$NC"

# Copy individual files
for f in "${USER_FILES[@]}"; do
    if [ -f "$VSCODE_USER_DIR/$f" ]; then
        cp "$VSCODE_USER_DIR/$f" "$STAGE_DIR/User/$f"
        echo "  ✓ User/$f"
    else
        echo "  - User/$f (not present)"
    fi
done

# Copy directories
for d in "${USER_DIRS[@]}"; do
    if [ -d "$VSCODE_USER_DIR/$d" ]; then
        cp -R "$VSCODE_USER_DIR/$d" "$STAGE_DIR/User/$d"
        COUNT=$(find "$STAGE_DIR/User/$d" -type f | wc -l | tr -d ' ')
        echo "  ✓ User/$d/ ($COUNT files)"
    else
        echo "  - User/$d/ (not present)"
    fi
done

# Export extension list
if [ "$HAS_CODE_CLI" = true ]; then
    EXT_FILE="$STAGE_DIR/extensions.txt"
    code --list-extensions --show-versions > "$EXT_FILE" 2>/dev/null
    EXT_COUNT=$(wc -l < "$EXT_FILE" | tr -d ' ')
    echo "  ✓ extensions.txt ($EXT_COUNT extensions listed)"
else
    echo "  - extensions.txt (skipped — code CLI not found)"
fi

# Add a small README inside the archive
cat > "$STAGE_DIR/README.txt" <<EOF
VS Code backup taken on: $(date)
From host: $(hostname)
VS Code user dir: $VSCODE_USER_DIR

Contents:
- User/        : settings.json, keybindings.json, snippets/, profiles/, etc.
- extensions.txt : list of installed extensions (one per line, with version)

To restore on a new Mac, use: restore-vscode.sh <this-archive>
EOF

# Compress
ARCHIVE="${OUTPUT_DIR}/${STAGE_NAME}.tar.gz"
print_message "" "$NC"

if [ "$USE_PASSWORD" = true ]; then
    if ! command -v openssl >/dev/null 2>&1; then
        print_message "Error: openssl not found. Re-run with --no-password or install openssl." "$RED"
        rm -rf "$STAGING"
        exit 1
    fi
    print_message "🔒 Archive will be encrypted with AES-256-CBC" "$BLUE"
    print_message "" "$NC"

    PASSWORD=""
    ATTEMPTS=0
    while [ $ATTEMPTS -lt 3 ]; do
        echo -n "Enter password: "
        read_secret PASSWORD
        echo -n "Confirm password: "
        read_secret PASSWORD_CONFIRM
        if [ -z "$PASSWORD" ]; then
            print_message "Password cannot be empty." "$RED"
        elif [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
            print_message "Passwords do not match. Try again." "$RED"
        else
            break
        fi
        ATTEMPTS=$((ATTEMPTS + 1))
    done

    if [ -z "$PASSWORD" ] || [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
        print_message "Too many failed attempts. Aborted." "$RED"
        rm -rf "$STAGING"
        exit 1
    fi
fi

print_message "" "$NC"
print_message "Compressing..." "$YELLOW"
tar -czf "$ARCHIVE" -C "$STAGING" "$STAGE_NAME"

if [ $? -ne 0 ]; then
    print_message "Error: Compression failed" "$RED"
    rm -rf "$STAGING"
    exit 1
fi

FINAL_OUTPUT="$ARCHIVE"
if [ "$USE_PASSWORD" = true ]; then
    print_message "Encrypting..." "$YELLOW"
    ENCRYPTED="${ARCHIVE}.enc"
    if ! openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 \
        -in "$ARCHIVE" -out "$ENCRYPTED" \
        -pass pass:"$PASSWORD" 2>/dev/null; then
        print_message "Error: Encryption failed" "$RED"
        rm -f "$ENCRYPTED"
        rm -rf "$STAGING"
        exit 1
    fi
    rm -f "$ARCHIVE"
    FINAL_OUTPUT="$ENCRYPTED"
    PASSWORD=""
fi

rm -rf "$STAGING"

# Report
SIZE="$(du -h "$FINAL_OUTPUT" | cut -f1)"
print_message "" "$NC"
print_message "Done!" "$GREEN"
print_message "Archive: $FINAL_OUTPUT" "$GREEN"
print_message "Size:    $SIZE" "$GREEN"
print_message "" "$NC"
print_message "To restore on the new Mac:" "$BLUE"
echo "  ./restore-vscode.sh $(basename "$FINAL_OUTPUT")"
