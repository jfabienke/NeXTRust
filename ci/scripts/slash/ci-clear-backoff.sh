#!/usr/bin/env bash
# ---
# argument-hint: ""
# ---
# ci/scripts/slash/ci-clear-backoff.sh - Clear failure backoff
#
# Purpose: Remove backoff file to allow retrying a poisoned commit
# Usage: /ci-clear-backoff
# Security: No arguments needed, operates on current commit

source ci/scripts/slash/common.sh

# Check write permission
check_write_permission

# Acquire lock for mutation
acquire_command_lock

# Get current commit SHA
COMMIT_SHA="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo "unknown")}"

if [[ "$COMMIT_SHA" == "unknown" ]]; then
    post_error "Could not determine current commit SHA"
    exit 1
fi

# Check if backoff file exists
BACKOFF_FILE=".claude/backoff/${COMMIT_SHA}"

if [[ ! -f "$BACKOFF_FILE" ]]; then
    post_response "ℹ️ No backoff found for commit \`${COMMIT_SHA:0:7}\`. The commit is not blocked."
    log_command "success" "no_backoff_found"
    exit 0
fi

# Read current failure count
FAILURE_COUNT=$(cat "$BACKOFF_FILE" 2>/dev/null || echo "0")

# Remove backoff file
if rm -f "$BACKOFF_FILE"; then
    RESPONSE="✅ Cleared backoff for commit \`${COMMIT_SHA:0:7}\`

**Previous failure count**: $FAILURE_COUNT
**Status**: Ready to retry

You can now trigger a new build without hitting the failure limit."
    
    post_success "$RESPONSE"
    log_command "success" "failures=$FAILURE_COUNT"
    
    # Also update status to record backoff clear
    if [[ -x "ci/scripts/status-append.py" ]]; then
        python3 ci/scripts/status-append.py "backoff_cleared" \
            "{\"commit\": \"$COMMIT_SHA\", \"previous_failures\": $FAILURE_COUNT, \"cleared_by\": \"${CI_TRIGGERED_BY:-unknown}\"}"
    fi
else
    post_error "Failed to clear backoff file. Please check permissions."
    log_command "failed" "permission_error"
    exit 1
fi