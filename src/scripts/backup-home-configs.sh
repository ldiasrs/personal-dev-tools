#!/bin/bash

# Backup common home folder configs (dotfiles, SSH, AWS, git, editor configs, etc.)
# into a timestamped, password-encrypted tar.gz archive.
# Designed for Mac-to-Mac migration.
# Usage: ./backup-home-configs.sh [output-dir] [--no-password]
#   output-dir    : defaults to ~/Documents
#   --no-password : produce an UNENCRYPTED archive (not recommended — contains SSH keys, AWS creds!)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_message() {
    echo -e "${2}${1}${NC}"
}

# Read SECRET input (no echo) — works in pipelines via /dev/tty, falls back to stdin
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

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="${OUTPUT_DIR}/home-configs-${TIMESTAMP}.tar.gz"
MANIFEST="/tmp/home-configs-manifest-${TIMESTAMP}.txt"

# Configs to back up (relative to $HOME). Missing ones are silently skipped.
CONFIGS=(
    # Shell
    ".zshrc"
    ".zprofile"
    ".zshenv"
    ".bashrc"
    ".bash_profile"
    ".bash_aliases"
    ".profile"
    ".inputrc"

    # Git
    ".gitconfig"
    ".gitignore_global"
    ".gitconfig.local"

    # SSH (config + known_hosts + keys)
    ".ssh"

    # AWS / cloud
    ".aws"
    ".gcloud"
    ".kube/config"
    ".docker/config.json"

    # Package managers
    ".npmrc"
    ".yarnrc"
    ".yarnrc.yml"
    ".nvmrc"

    # Python
    ".pythonrc"
    ".python_history"

    # Editors
    ".vimrc"
    ".vim"
    ".ideavimrc"
    ".tmux.conf"

    # Homebrew
    "Brewfile"
    ".Brewfile"

    # Claude Code (skills, settings, keybindings, plans, memory)
    ".claude"

    # GitHub CLI
    ".config/gh"

    # Modern config dir for various tools
    ".config/ghostty"
    ".config/starship.toml"
    ".config/nvim"
    ".config/zellij"
    ".config/wezterm"
    ".config/atuin"
    ".config/karabiner"

    # Asdf / pyenv / nvm (just configs, not installs)
    ".tool-versions"
    ".asdfrc"
    ".pyenv/version"
    ".nvm/default-packages"

    # Misc
    ".editorconfig"
)

# Files to EXCLUDE from --exclude (apply inside whatever we include)
EXCLUDES=(
    "node_modules"
    ".cache"
    "Cache"
    "CachedData"
    "logs"
    "*.log"
    "tmp"
    ".DS_Store"
    ".claude/projects/*/memory"   # auto-memory is per-machine; can re-init on new Mac
    ".claude/statsig"
    ".claude/shell-snapshots"
    ".claude/todos"
    ".claude/ide"
    ".vscode-cli"
    ".npm/_cacache"
    ".yarn/cache"
)

# Build the list of paths that actually exist
EXISTING=()
SKIPPED=()
for c in "${CONFIGS[@]}"; do
    if [ -e "$HOME/$c" ]; then
        EXISTING+=("$c")
    else
        SKIPPED+=("$c")
    fi
done

if [ ${#EXISTING[@]} -eq 0 ]; then
    print_message "Error: no configs found to back up" "$RED"
    exit 1
fi

# Build tar exclude args
EXCLUDE_ARGS=()
for e in "${EXCLUDES[@]}"; do
    EXCLUDE_ARGS+=(--exclude="$e")
done

# Show what's being backed up
print_message "" "$NC"
print_message "Backing up ${#EXISTING[@]} config(s) from \$HOME → $ARCHIVE" "$BLUE"
print_message "" "$NC"
print_message "Included:" "$YELLOW"
for c in "${EXISTING[@]}"; do
    echo "  ✓ $c"
done

if [ ${#SKIPPED[@]} -gt 0 ]; then
    print_message "" "$NC"
    print_message "Skipped (not present on this Mac):" "$YELLOW"
    for c in "${SKIPPED[@]}"; do
        echo "  - $c"
    done
fi

# Heads-up on sensitive contents
print_message "" "$NC"
print_message "⚠️  This archive contains sensitive data (.ssh keys, .aws credentials, tokens)." "$YELLOW"
if [ "$USE_PASSWORD" = true ]; then
    print_message "    It WILL be encrypted with AES-256-CBC." "$GREEN"
else
    print_message "    --no-password mode: archive will NOT be encrypted. Use at your own risk." "$RED"
fi
print_message "" "$NC"

# Prompt for password BEFORE compressing
PASSWORD=""
if [ "$USE_PASSWORD" = true ]; then
    if ! command -v openssl >/dev/null 2>&1; then
        print_message "Error: openssl not found. Re-run with --no-password or install openssl." "$RED"
        exit 1
    fi

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
        exit 1
    fi
    print_message "" "$NC"
fi

# Run tar
print_message "Compressing..." "$YELLOW"
tar -czf "$ARCHIVE" \
    "${EXCLUDE_ARGS[@]}" \
    -C "$HOME" \
    "${EXISTING[@]}" 2> "$MANIFEST"

# tar can emit harmless "file changed as we read it" warnings — only fail on hard errors
RESULT=$?
if [ $RESULT -ne 0 ] && [ ! -f "$ARCHIVE" ]; then
    print_message "Error: Compression failed" "$RED"
    cat "$MANIFEST" >&2
    rm -f "$MANIFEST"
    exit 1
fi

# Encrypt
FINAL_OUTPUT="$ARCHIVE"
DECRYPT_SCRIPT=""
if [ "$USE_PASSWORD" = true ]; then
    print_message "Encrypting with AES-256-CBC..." "$YELLOW"
    ENCRYPTED="${ARCHIVE}.enc"
    if ! openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 \
        -in "$ARCHIVE" -out "$ENCRYPTED" \
        -pass pass:"$PASSWORD" 2>/dev/null; then
        print_message "Error: Encryption failed" "$RED"
        rm -f "$ENCRYPTED"
        exit 1
    fi
    rm -f "$ARCHIVE"
    FINAL_OUTPUT="$ENCRYPTED"
    PASSWORD=""

    # Generate companion decrypt script (extracts to $HOME)
    DECRYPT_SCRIPT="${OUTPUT_DIR}/home-configs-${TIMESTAMP}.decrypt.sh"
    ENC_BASENAME="$(basename "$ENCRYPTED")"
    DEC_BASENAME="$(basename "$ARCHIVE")"
    cat > "$DECRYPT_SCRIPT" <<EOF
#!/bin/bash
# Auto-generated decrypt script for: ${ENC_BASENAME}
# Run from the same directory as the encrypted archive.
# Extracts INTO \$HOME (your home folder).

set -e

ARCHIVE_ENC="${ENC_BASENAME}"
ARCHIVE_DEC="${DEC_BASENAME}"
EOF
    cat >> "$DECRYPT_SCRIPT" <<'EOF'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENC_PATH="$SCRIPT_DIR/$ARCHIVE_ENC"
DEC_PATH="$SCRIPT_DIR/$ARCHIVE_DEC"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ ! -f "$ENC_PATH" ]; then
    echo -e "${RED}Error: encrypted archive not found: $ENC_PATH${NC}"
    exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
    echo -e "${RED}Error: openssl not found${NC}"
    exit 1
fi

# Confirm before clobbering home configs
echo -e "${YELLOW}⚠️  This will extract dotfiles/configs into: $HOME${NC}"
echo -e "${YELLOW}    Existing files with the same name may be overwritten.${NC}"
echo -n "Proceed? [y/N] "
read -r CONFIRM
case "$CONFIRM" in
    y|Y|yes) ;;
    *) echo "Aborted."; exit 0 ;;
esac

# Prompt for password
echo -n "Enter password: "
if [ -t 0 ]; then
    read -rs PASSWORD
else
    { read -rs PASSWORD < /dev/tty; } 2>/dev/null || read -rs PASSWORD
fi
echo

if [ -z "$PASSWORD" ]; then
    echo -e "${RED}Empty password. Aborted.${NC}"
    exit 1
fi

# Decrypt
echo -e "${YELLOW}Decrypting...${NC}"
if ! openssl enc -aes-256-cbc -d -pbkdf2 -iter 200000 \
    -in "$ENC_PATH" -out "$DEC_PATH" \
    -pass pass:"$PASSWORD" 2>/dev/null; then
    echo -e "${RED}Error: decryption failed (wrong password?)${NC}"
    rm -f "$DEC_PATH"
    exit 1
fi
PASSWORD=""

# Extract into $HOME
echo -e "${YELLOW}Extracting into $HOME...${NC}"
if ! tar -xzf "$DEC_PATH" -C "$HOME"; then
    echo -e "${RED}Error: extraction failed${NC}"
    exit 1
fi

# Cleanup intermediate .tar.gz
rm -f "$DEC_PATH"

echo -e "${GREEN}Done!${NC}"
echo -e "${BLUE}Configs restored to: $HOME${NC}"
echo -e "${YELLOW}Tip: restart your shell or 'source ~/.zshrc' to pick up shell config changes.${NC}"
EOF
    chmod +x "$DECRYPT_SCRIPT"
fi

# Done
SIZE="$(du -h "$FINAL_OUTPUT" | cut -f1)"
print_message "" "$NC"
print_message "Done!" "$GREEN"
print_message "Archive: $FINAL_OUTPUT" "$GREEN"
print_message "Size:    $SIZE" "$GREEN"
print_message "" "$NC"

if [ "$USE_PASSWORD" = true ]; then
    print_message "🔓 Companion decrypt script generated:" "$BLUE"
    print_message "   $DECRYPT_SCRIPT" "$GREEN"
    print_message "" "$NC"
    print_message "On the new Mac, copy BOTH files to the same folder and run:" "$BLUE"
    echo "  ./$(basename "$DECRYPT_SCRIPT")"
    print_message "" "$NC"
    print_message "Manual decrypt (alternative):" "$BLUE"
    echo "  openssl enc -aes-256-cbc -d -pbkdf2 -iter 200000 \\"
    echo "    -in $(basename "$FINAL_OUTPUT") \\"
    echo "    -out $(basename "$ARCHIVE")"
    echo "  tar -xzf $(basename "$ARCHIVE") -C \$HOME"
else
    print_message "To restore on the new Mac:" "$BLUE"
    echo "  tar -xzf $(basename "$ARCHIVE") -C \$HOME"
fi

rm -f "$MANIFEST"
