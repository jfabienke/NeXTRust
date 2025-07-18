#!/bin/bash
# hooks/dispatcher.d/common/idempotency.sh - Idempotency check functions
#
# Purpose: Prevent duplicate operations using composite keys

# Generate composite idempotency key
generate_idempotency_key() {
    local session_id=${1:-$SESSION_ID}
    local commit_sha=${COMMIT_SHA:-$(git rev-parse HEAD 2>/dev/null || echo "no-commit")}
    local run_id=${RUN_ID:-"local"}
    local run_attempt=${RUN_ATTEMPT:-"1"}
    
    echo -n "${session_id}:${commit_sha}:${run_id}:${run_attempt}" | sha256sum | cut -d' ' -f1
}

# Check if operation should be skipped
check_idempotency() {
    local key=$(generate_idempotency_key "$SESSION_ID")
    local session_dir=".claude/sessions"
    local session_file="${session_dir}/${key}"
    
    mkdir -p "$session_dir" 2>/dev/null || true
    
    if [[ -f "$session_file" ]]; then
        echo "[$(date)] Skipping duplicate operation: $key"
        return 1  # Should skip
    fi
    
    # Mark as processed
    touch "$session_file"
    
    # Clean old session files (older than 7 days)
    find "$session_dir" -type f -mtime +7 -delete 2>/dev/null || true
    
    return 0  # Should proceed
}

# Mark operation as completed
mark_idempotency_complete() {
    local key=$(generate_idempotency_key "$SESSION_ID")
    local session_file=".claude/sessions/${key}"
    
    if [[ -f "$session_file" ]]; then
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${session_file}.completed"
    fi
}