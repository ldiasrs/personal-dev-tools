#!/bin/bash

PROJECTS="${PROJECTS:-$HOME/Documents/projects}"
APPS_DIR="$PROJECTS/apps"
CURSOR_DIR="$HOME/.cursor"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Find and kill Node.js processes"
    echo ""
    echo "Options:"
    echo "  -f, --force    Force kill without confirmation"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "Example:"
    echo "  $0              # Show processes and ask for confirmation"
    echo "  $0 --force      # Force kill all Node.js processes"
}

# Parse command line arguments
FORCE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Function to find Node.js processes and group them by working directory
find_node_processes() {
    # Get all node processes with their working directories
    ps -eo pid,ppid,user,%cpu,%mem,command | grep -i "[n]ode" | grep -v "grep" | grep -v "node-kills.sh" | while read -r line; do
        pid=$(echo "$line" | awk '{print $1}')
        # Get working directory for the process
        wd=$(lsof -p "$pid" 2>/dev/null | grep "cwd" | awk '{print $9}')
        # Get the full command path
        cmd=$(lsof -p "$pid" 2>/dev/null | grep "txt" | awk '{print $9}')
        
        # Skip processes from Cursor application (check both working directory and command path)
        if [[ -n "$wd" && "$wd" != "$CURSOR_DIR"/* ]] && \
           [[ -z "$cmd" || ! "$cmd" =~ ^/Applications/Cursor.app/Contents/Frameworks/Cursor ]]; then
            echo "$wd|$line"
        fi
    done
}

# Function to kill processes
kill_processes() {
    local processes
    processes=$(find_node_processes)
    
    if [[ -z "$processes" ]]; then
        echo -e "${GREEN}No Node.js processes found.${NC}"
        return
    fi

    # Group processes by directory
    echo -e "${YELLOW}Found Node.js processes grouped by directory:${NC}"
    echo "----------------------------------------"
    
    # Initialize arrays to store PIDs
    declare -a apps_pids
    declare -a other_pids
    
    # First show apps directory processes
    echo -e "${BLUE}Processes in $APPS_DIR:${NC}"
    echo "----------------------------------------"
    while IFS="|" read -r wd line; do
        if [[ "$wd" == "$APPS_DIR" ]]; then
            pid=$(echo "$line" | awk '{print $1}')
            apps_pids+=("$pid")
            printf "PID: %-8s CPU: %-6s MEM: %-6s Command: %s\n" \
                $(echo "$line" | awk '{print $1, $4, $5, $6}')
        fi
    done <<< "$processes"

    # Then show other directories
    echo -e "\n${BLUE}Processes in other directories:${NC}"
    echo "----------------------------------------"
    while IFS="|" read -r wd line; do
        if [[ "$wd" != "$APPS_DIR" ]]; then
            pid=$(echo "$line" | awk '{print $1}')
            other_pids+=("$pid")
            echo -e "${YELLOW}Directory: $wd${NC}"
            printf "PID: %-8s CPU: %-6s MEM: %-6s Command: %s\n" \
                $(echo "$line" | awk '{print $1, $4, $5, $6}')
            echo "----------------------------------------"
        fi
    done <<< "$processes"

    # Combine all PIDs into a single array
    all_pids=("${apps_pids[@]}" "${other_pids[@]}")
    
    if [[ ${#all_pids[@]} -eq 0 ]]; then
        echo -e "${GREEN}No processes to kill.${NC}"
        return
    fi

    if [[ "$FORCE" == "true" ]]; then
        echo -e "${RED}Force killing all Node.js processes...${NC}"
        for pid in "${all_pids[@]}"; do
            if kill -9 "$pid" 2>/dev/null; then
                echo -e "${GREEN}Killed process $pid${NC}"
            else
                echo -e "${RED}Failed to kill process $pid${NC}"
            fi
        done
        echo -e "${GREEN}Kill operation completed.${NC}"
    else
        echo -e "${YELLOW}Do you want to kill these processes? (y/N)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            echo -e "${RED}Killing Node.js processes...${NC}"
            for pid in "${all_pids[@]}"; do
                if kill -9 "$pid" 2>/dev/null; then
                    echo -e "${GREEN}Killed process $pid${NC}"
                else
                    echo -e "${RED}Failed to kill process $pid${NC}"
                fi
            done
            echo -e "${GREEN}Kill operation completed.${NC}"
        else
            echo -e "${GREEN}Operation cancelled.${NC}"
        fi
    fi
}

# Main execution
echo -e "${YELLOW}Searching for Node.js processes...${NC}"
kill_processes 