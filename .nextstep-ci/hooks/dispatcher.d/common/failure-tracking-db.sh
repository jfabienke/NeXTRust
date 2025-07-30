#!/bin/bash
# hooks/dispatcher.d/common/failure-tracking-db.sh - Persistent failure tracking
#
# Purpose: Track command failures persistently across sessions
# Provides: get_failure_count_for_command(), increment_failure_count_for_command()
#
set -uo pipefail

# Failure database location
FAILURE_DB_DIR="${FAILURE_DB_DIR:-.claude/failure-tracking}"
FAILURE_DB_FILE="$FAILURE_DB_DIR/failures.json"

# Ensure database directory exists
ensure_failure_db() {
    mkdir -p "$FAILURE_DB_DIR" 2>/dev/null || true
    
    # Initialize empty database if it doesn't exist
    if [[ ! -f "$FAILURE_DB_FILE" ]]; then
        echo '{"failures": {}, "last_updated": ""}' > "$FAILURE_DB_FILE"
    fi
}

# Get failure count for a specific command
get_failure_count_for_command() {
    local command="$1"
    ensure_failure_db
    
    # Sanitize command for use as JSON key
    local sanitized_command=$(echo "$command" | tr -d '\n' | sed 's/[^a-zA-Z0-9_.-]/_/g')
    
    # Get count from database
    local count=$(jq -r --arg cmd "$sanitized_command" '.failures[$cmd] // 0' "$FAILURE_DB_FILE" 2>/dev/null || echo 0)
    
    echo "$count"
}

# Increment failure count for a command
increment_failure_count_for_command() {
    local command="$1"
    ensure_failure_db
    
    # Sanitize command
    local sanitized_command=$(echo "$command" | tr -d '\n' | sed 's/[^a-zA-Z0-9_.-]/_/g')
    
    # Use file locking to prevent race conditions
    local lock_file="$FAILURE_DB_DIR/.lock"
    local timeout=5
    local elapsed=0
    
    # Try to acquire lock
    while ! (set -C; echo $$ > "$lock_file") 2>/dev/null; do
        if [[ $elapsed -ge $timeout ]]; then
            echo "[WARNING] Could not acquire failure DB lock" >&2
            return 1
        fi
        sleep 0.1
        elapsed=$((elapsed + 1))
    done
    
    # Update failure count
    local temp_file="$FAILURE_DB_FILE.tmp"
    jq --arg cmd "$sanitized_command" --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .failures[$cmd] = ((.failures[$cmd] // 0) + 1) |
        .last_updated = $time
    ' "$FAILURE_DB_FILE" > "$temp_file" 2>/dev/null
    
    # Replace original file if update succeeded
    if [[ -s "$temp_file" ]]; then
        mv "$temp_file" "$FAILURE_DB_FILE"
    else
        echo "[WARNING] Failed to update failure database" >&2
    fi
    
    # Release lock
    rm -f "$lock_file"
}

# Reset failure count for a command (for testing or after fix)
reset_failure_count_for_command() {
    local command="$1"
    ensure_failure_db
    
    local sanitized_command=$(echo "$command" | tr -d '\n' | sed 's/[^a-zA-Z0-9_.-]/_/g')
    
    # Use same locking mechanism
    local lock_file="$FAILURE_DB_DIR/.lock"
    local timeout=5
    local elapsed=0
    
    while ! (set -C; echo $$ > "$lock_file") 2>/dev/null; do
        if [[ $elapsed -ge $timeout ]]; then
            echo "[WARNING] Could not acquire failure DB lock" >&2
            return 1
        fi
        sleep 0.1
        elapsed=$((elapsed + 1))
    done
    
    # Remove command from failures
    local temp_file="$FAILURE_DB_FILE.tmp"
    jq --arg cmd "$sanitized_command" --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        del(.failures[$cmd]) |
        .last_updated = $time
    ' "$FAILURE_DB_FILE" > "$temp_file" 2>/dev/null
    
    if [[ -s "$temp_file" ]]; then
        mv "$temp_file" "$FAILURE_DB_FILE"
    fi
    
    rm -f "$lock_file"
}

# Get all commands with failure counts
get_all_failure_counts() {
    ensure_failure_db
    
    jq -r '.failures | to_entries | .[] | "\(.key):\(.value)"' "$FAILURE_DB_FILE" 2>/dev/null || true
}

# Clean up old failure entries (older than N days)
cleanup_old_failures() {
    local days="${1:-30}"
    echo "[INFO] Cleanup not implemented yet - would remove failures older than $days days"
    # TODO: Implement cleanup based on last failure timestamp
}