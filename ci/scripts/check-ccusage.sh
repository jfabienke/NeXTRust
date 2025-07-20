#!/bin/bash
# check-ccusage.sh - Check if ccusage command is available
# This script checks if the Claude Code usage tool is available in PATH

# Function for use in other scripts
ensure_ccusage_or_skip() {
    if command -v ccusage &> /dev/null; then
        return 0
    else
        echo "[$(date)] ccusage not available, skipping usage capture" >&2
        return 1
    fi
}

# Main script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -e
    
    # Check if ccusage is available
    if command -v ccusage &> /dev/null; then
        echo "✓ ccusage command found at: $(which ccusage)"
        exit 0
    else
        echo "✗ ccusage command not found in PATH"
        echo "  Claude Code usage tracking will not be available"
        exit 1
    fi
fi