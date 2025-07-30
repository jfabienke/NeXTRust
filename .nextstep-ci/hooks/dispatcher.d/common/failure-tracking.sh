#!/bin/bash
# hooks/dispatcher.d/common/failure-tracking.sh - Track and limit failure loops
#
# Purpose: Prevent infinite failure loops on poisoned commits

# Get current failure count
get_failure_count() {
    local commit_sha=${1:-$COMMIT_SHA}
    local backoff_file=".claude/backoff/${commit_sha}"
    
    if [[ -f "$backoff_file" ]]; then
        cat "$backoff_file" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Increment failure count
increment_failure_count() {
    local commit_sha=${1:-$COMMIT_SHA}
    local backoff_dir=".claude/backoff"
    local backoff_file="${backoff_dir}/${commit_sha}"
    
    mkdir -p "$backoff_dir" 2>/dev/null || true
    
    local current_count=$(get_failure_count "$commit_sha")
    local new_count=$((current_count + 1))
    
    echo "$new_count" > "$backoff_file"
    echo "[$(date)] Failure count for $commit_sha: $new_count"
    
    # Clean old backoff files (older than 30 days)
    find "$backoff_dir" -type f -mtime +30 -delete 2>/dev/null || true
    
    return $new_count
}

# Check if we should bail out
check_failure_limit() {
    local commit_sha=${1:-$COMMIT_SHA}
    local max_failures=${2:-3}
    local failure_count=$(get_failure_count "$commit_sha")
    
    if [[ "$failure_count" -ge "$max_failures" ]]; then
        echo "::error::Commit $commit_sha has failed $failure_count times. Push new commit to retry."
        return 1
    fi
    
    return 0
}

# Reset failure count (e.g., after successful build)
reset_failure_count() {
    local commit_sha=${1:-$COMMIT_SHA}
    local backoff_file=".claude/backoff/${commit_sha}"
    
    if [[ -f "$backoff_file" ]]; then
        rm -f "$backoff_file"
        echo "[$(date)] Reset failure count for $commit_sha"
    fi
}