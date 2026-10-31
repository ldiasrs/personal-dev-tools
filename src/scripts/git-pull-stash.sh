#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
    echo -e "${2}${1}${NC}"
}

# Check if we're in a git repository
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    print_message "Error: Not a git repository" "$RED"
    exit 1
fi

# Check if there are any changes to stash
if git diff --quiet && git diff --cached --quiet; then
    print_message "No local changes to stash, proceeding with pull..." "$YELLOW"
else
    print_message "Stashing local changes..." "$YELLOW"
    if ! git stash save "Temporary stash before pull"; then
        print_message "Error: Failed to stash changes" "$RED"
        exit 1
    fi
    print_message "Changes stashed successfully" "$GREEN"
fi

# Pull changes
print_message "Pulling latest changes..." "$YELLOW"
if ! git pull; then
    print_message "Error: Failed to pull changes" "$RED"
    # Try to restore stash if pull failed
    if git stash list | grep -q "Temporary stash before pull"; then
        print_message "Restoring stashed changes..." "$YELLOW"
        git stash pop
    fi
    exit 1
fi
print_message "Changes pulled successfully" "$GREEN"

# If we stashed changes, try to apply them back
if git stash list | grep -q "Temporary stash before pull"; then
    print_message "Applying stashed changes back..." "$YELLOW"
    if ! git stash pop; then
        print_message "Warning: There were conflicts while applying stashed changes" "$RED"
        print_message "Please resolve the conflicts manually" "$RED"
        exit 1
    fi
    print_message "Stashed changes applied successfully" "$GREEN"
fi

print_message "All operations completed successfully!" "$GREEN"