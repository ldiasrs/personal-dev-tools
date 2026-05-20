#!/bin/bash

# Compress a project folder into a timestamped, password-encrypted tar.gz.
# Interactively shows the biggest items and lets you include/exclude each.
# Output is encrypted with AES-256-CBC + PBKDF2 (openssl) into a .tar.gz.enc file.
# Usage: ./compress-project.sh <folder-path> [--yes] [--no-password]
#   --yes         : skip interactive item review (uses defaults)
#   --no-password : produce an UNENCRYPTED .tar.gz (not recommended)

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

# Read user input — prefer /dev/tty (works in pipelines) but fall back to stdin
read_input() {
    local __var="$1"
    # If stdin is already a terminal, just read from it
    if [ -t 0 ]; then
        read -r "$__var"
        return
    fi
    # Otherwise try /dev/tty silently; if that fails, fall back to stdin
    { read -r "$__var" < /dev/tty; } 2>/dev/null || read -r "$__var"
}

# Read SECRET input (no echo) — same fallback strategy as read_input
read_secret() {
    local __var="$1"
    if [ -t 0 ]; then
        read -rs "$__var"
        echo  # newline after silent read
        return
    fi
    { read -rs "$__var" < /dev/tty; } 2>/dev/null || read -rs "$__var"
    echo
}

# 1. Parse args
TARGET=""
SKIP_PROMPT=false
USE_PASSWORD=true
for arg in "$@"; do
    case "$arg" in
        --yes|-y) SKIP_PROMPT=true ;;
        --no-password) USE_PASSWORD=false ;;
        *) TARGET="$arg" ;;
    esac
done

if [ -z "$TARGET" ]; then
    print_message "Usage: $(basename "$0") <folder-path> [--yes] [--no-password]" "$RED"
    exit 1
fi

if [ ! -d "$TARGET" ]; then
    print_message "Error: '$TARGET' is not a directory" "$RED"
    exit 1
fi

# 2. Resolve absolute paths
TARGET_ABS="$(cd "$TARGET" && pwd)"
PARENT_DIR="$(dirname "$TARGET_ABS")"
BASENAME="$(basename "$TARGET_ABS")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="${PARENT_DIR}/${BASENAME}-${TIMESTAMP}.tar.gz"

# 3. Defaults — items excluded unless user opts to include
DEFAULT_EXCLUDES=("node_modules" "dist" "build" ".next" ".turbo" ".nx/cache" ".DS_Store")

is_default_excluded() {
    local item="$1"
    local base="${item##*/}"  # last path segment
    for ex in "${DEFAULT_EXCLUDES[@]}"; do
        if [ "$base" = "$ex" ] || [ "$item" = "$ex" ]; then
            return 0
        fi
    done
    return 1
}

# 4. Scan biggest items (depth 1 + 2, items >= 1MB)
print_message "" "$NC"
print_message "Scanning '$BASENAME' for biggest items..." "$YELLOW"

# macOS du: -h human, -d depth. Combine depth 1 and 2 to surface nested heavy folders.
BIG_ITEMS_FILE="$(mktemp)"
(
    cd "$TARGET_ABS" && du -h -d 2 2>/dev/null \
        | awk '$1 ~ /[MG]$/ { print }' \
        | awk '$2 != "." { print }' \
        | sort -hr \
        | head -20
) > "$BIG_ITEMS_FILE"

if [ ! -s "$BIG_ITEMS_FILE" ]; then
    print_message "No items larger than ~1MB found. Using defaults." "$GRAY"
    SKIP_PROMPT=true
fi

# 5. Build interactive include/exclude state
# Strategy: start with defaults, present each big item, let user toggle.
# FINAL_EXCLUDES holds the final --exclude list passed to tar.
FINAL_EXCLUDES=("${DEFAULT_EXCLUDES[@]}")

# Track items the user explicitly INCLUDED (will be removed from FINAL_EXCLUDES)
USER_INCLUDED=()
# Track items the user explicitly EXCLUDED (added to FINAL_EXCLUDES)
USER_EXCLUDED=()

remove_from_excludes() {
    local item="$1"
    local new_list=()
    for ex in "${FINAL_EXCLUDES[@]}"; do
        if [ "$ex" != "$item" ] && [ "$ex" != "${item##*/}" ]; then
            new_list+=("$ex")
        fi
    done
    FINAL_EXCLUDES=("${new_list[@]}")
}

if [ "$SKIP_PROMPT" = false ]; then
    print_message "" "$NC"
    print_message "Biggest items found — review each (Enter = keep default):" "$BLUE"
    print_message "  [i] include   [x] exclude   [Enter] keep default   [q] finish review" "$GRAY"
    print_message "" "$NC"

    while IFS=$'\t' read -r SIZE ITEM_PATH; do
        # Skip blank lines
        [ -z "$ITEM_PATH" ] && continue
        # Strip leading "./"
        ITEM="${ITEM_PATH#./}"

        # Determine default state
        if is_default_excluded "$ITEM"; then
            DEFAULT_STATE="EXCLUDED"
            STATE_COLOR="$RED"
        else
            DEFAULT_STATE="INCLUDED"
            STATE_COLOR="$GREEN"
        fi

        # Pretty print
        printf "  %-8s  %-50s  " "$SIZE" "$ITEM"
        echo -en "${STATE_COLOR}${DEFAULT_STATE}${NC}"
        echo -n "  → "

        # Read single keystroke (or full line if user types something)
        read_input CHOICE

        case "$CHOICE" in
            i|I|include)
                if is_default_excluded "$ITEM"; then
                    remove_from_excludes "$ITEM"
                    USER_INCLUDED+=("$ITEM")
                    print_message "      → will be INCLUDED" "$GREEN"
                else
                    print_message "      → already included (no change)" "$GRAY"
                fi
                ;;
            x|X|exclude)
                if ! is_default_excluded "$ITEM"; then
                    FINAL_EXCLUDES+=("$ITEM")
                    USER_EXCLUDED+=("$ITEM")
                    print_message "      → will be EXCLUDED" "$RED"
                else
                    print_message "      → already excluded (no change)" "$GRAY"
                fi
                ;;
            q|Q|quit)
                print_message "      Skipping remaining items, using current settings" "$GRAY"
                break
                ;;
            *)
                # Empty / anything else = keep default, no echo needed
                ;;
        esac
    done < "$BIG_ITEMS_FILE"
fi

rm -f "$BIG_ITEMS_FILE"

# 6. Summary before compress
print_message "" "$NC"
print_message "=== Compression Plan ===" "$BLUE"
print_message "Source:  $TARGET_ABS" "$NC"
print_message "Archive: $ARCHIVE" "$NC"
print_message "" "$NC"
print_message "Excluding:" "$YELLOW"
for ex in "${FINAL_EXCLUDES[@]}"; do
    echo "  - $ex"
done
if [ ${#USER_INCLUDED[@]} -gt 0 ]; then
    print_message "" "$NC"
    print_message "Forced INCLUDE (overriding defaults):" "$GREEN"
    for inc in "${USER_INCLUDED[@]}"; do
        echo "  + $inc"
    done
fi

if [ "$USE_PASSWORD" = true ]; then
    print_message "" "$NC"
    print_message "🔒 Archive will be encrypted with AES-256-CBC (openssl)" "$BLUE"
fi

if [ "$SKIP_PROMPT" = false ]; then
    print_message "" "$NC"
    echo -n "Proceed with compression? [Y/n] "
    read_input CONFIRM
    case "$CONFIRM" in
        n|N|no) print_message "Aborted." "$RED"; exit 0 ;;
    esac
fi

# 6.5 Prompt for password BEFORE compressing (so user can abort if they cancel)
PASSWORD=""
if [ "$USE_PASSWORD" = true ]; then
    # Verify openssl is available
    if ! command -v openssl >/dev/null 2>&1; then
        print_message "Error: openssl not found. Re-run with --no-password or install openssl." "$RED"
        exit 1
    fi

    print_message "" "$NC"
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
fi

# 7. Build tar exclude args
EXCLUDE_ARGS=()
for ex in "${FINAL_EXCLUDES[@]}"; do
    EXCLUDE_ARGS+=(--exclude="$ex")
done

# 8. Compress
print_message "" "$NC"
print_message "Compressing..." "$YELLOW"
tar -czf "$ARCHIVE" \
    "${EXCLUDE_ARGS[@]}" \
    -C "$PARENT_DIR" "$BASENAME"

if [ $? -ne 0 ]; then
    print_message "Error: Compression failed" "$RED"
    exit 1
fi

# 8.5 Encrypt with openssl (if password set)
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
    # Remove the unencrypted intermediate
    rm -f "$ARCHIVE"
    FINAL_OUTPUT="$ENCRYPTED"
    # Wipe password var
    PASSWORD=""

    # Generate companion decrypt script
    DECRYPT_SCRIPT="${PARENT_DIR}/${BASENAME}-${TIMESTAMP}.decrypt.sh"
    ENC_BASENAME="$(basename "$ENCRYPTED")"
    DEC_BASENAME="$(basename "$ARCHIVE")"
    cat > "$DECRYPT_SCRIPT" <<EOF
#!/bin/bash
# Auto-generated decrypt script for: ${ENC_BASENAME}
# Run from the same directory as the encrypted archive.

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

# Extract
echo -e "${YELLOW}Extracting...${NC}"
if ! tar -xzf "$DEC_PATH" -C "$SCRIPT_DIR"; then
    echo -e "${RED}Error: extraction failed${NC}"
    exit 1
fi

# Cleanup intermediate .tar.gz
rm -f "$DEC_PATH"

echo -e "${GREEN}Done!${NC}"
echo -e "${BLUE}Extracted to: $SCRIPT_DIR${NC}"
EOF
    chmod +x "$DECRYPT_SCRIPT"
fi

# 9. Report result
SIZE="$(du -h "$FINAL_OUTPUT" | cut -f1)"
print_message "" "$NC"
print_message "Done!" "$GREEN"
print_message "Archive: $FINAL_OUTPUT" "$GREEN"
print_message "Size:    $SIZE" "$GREEN"

if [ "$USE_PASSWORD" = true ]; then
    print_message "" "$NC"
    print_message "🔓 Companion decrypt script generated:" "$BLUE"
    print_message "   $DECRYPT_SCRIPT" "$GREEN"
    print_message "" "$NC"
    print_message "On the new machine, copy BOTH files to the same folder and run:" "$BLUE"
    echo "  ./$(basename "$DECRYPT_SCRIPT")"
    print_message "" "$NC"
    print_message "Manual decrypt (alternative):" "$BLUE"
    echo "  openssl enc -aes-256-cbc -d -pbkdf2 -iter 200000 \\"
    echo "    -in $(basename "$FINAL_OUTPUT") \\"
    echo "    -out $(basename "$ARCHIVE")"
    echo "  tar -xzf $(basename "$ARCHIVE")"
fi
