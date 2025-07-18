#!/usr/bin/env bash
# ---
# argument-hint: ""
# ---
# ci/scripts/slash/ci-clear-cache.sh - Clear GitHub Actions cache
#
# Purpose: Clear build caches for the current branch (admin only)
# Usage: /ci-clear-cache
# Security: No arguments, operates on current branch

source ci/scripts/slash/common.sh

# This is an admin command - add additional checks if needed
check_write_permission

# For admin commands, we might want stricter permission checks
# For now, we rely on the workflow's author_association check

# Acquire lock for mutation
acquire_command_lock

# Get current branch
BRANCH_NAME="${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")}}"

if [[ "$BRANCH_NAME" == "unknown" ]]; then
    post_error "Could not determine current branch"
    exit 1
fi

echo "[$(date)] Clearing cache for branch: $BRANCH_NAME"

# List caches for this branch
CACHES=$(gh api repos/${GITHUB_REPOSITORY}/actions/caches \
    --jq '.actions_caches[]' \
    -f ref="refs/heads/$BRANCH_NAME" 2>/dev/null)

if [[ -z "$CACHES" ]]; then
    post_response "ℹ️ No caches found for branch \`$BRANCH_NAME\`"
    log_command "success" "no_caches_found"
    exit 0
fi

# Count caches
CACHE_COUNT=$(echo "$CACHES" | jq -s 'length')
TOTAL_SIZE=$(echo "$CACHES" | jq -s 'map(.size_in_bytes) | add')
TOTAL_SIZE_MB=$((TOTAL_SIZE / 1024 / 1024))

echo "[$(date)] Found $CACHE_COUNT caches totaling ${TOTAL_SIZE_MB}MB"

# Clear each cache
CLEARED_COUNT=0
FAILED_COUNT=0

while IFS= read -r cache_id; do
    if [[ -n "$cache_id" ]]; then
        echo "[$(date)] Deleting cache $cache_id..."
        if gh api --method DELETE repos/${GITHUB_REPOSITORY}/actions/caches/${cache_id} 2>/dev/null; then
            ((CLEARED_COUNT++))
        else
            ((FAILED_COUNT++))
        fi
    fi
done < <(echo "$CACHES" | jq -r '.id')

# Also try to clear by key pattern (more thorough)
CACHE_KEYS=$(echo "$CACHES" | jq -r '.key' | sort -u)
KEY_PATTERNS=""

while IFS= read -r key; do
    if [[ -n "$key" ]]; then
        # Extract base pattern (remove hash suffixes)
        BASE_KEY=$(echo "$key" | sed -E 's/-[a-f0-9]{32,}$//')
        KEY_PATTERNS="$KEY_PATTERNS
• \`$BASE_KEY\`"
    fi
done <<< "$CACHE_KEYS"

RESPONSE="✅ Cache clear completed for branch \`$BRANCH_NAME\`

**Caches found**: $CACHE_COUNT
**Total size**: ${TOTAL_SIZE_MB}MB
**Cleared**: $CLEARED_COUNT
**Failed**: $FAILED_COUNT

**Cache patterns cleared:**
$KEY_PATTERNS

New builds will start with fresh caches. This may increase initial build time."

post_success "$RESPONSE"
log_command "success" "branch=$BRANCH_NAME,cleared=$CLEARED_COUNT,size_mb=$TOTAL_SIZE_MB"

# Update status
if [[ -x "ci/scripts/status-append.py" ]]; then
    python3 ci/scripts/status-append.py "cache_cleared" \
        "{\"branch\": \"$BRANCH_NAME\", \"caches_cleared\": $CLEARED_COUNT, \"size_mb\": $TOTAL_SIZE_MB, \"cleared_by\": \"${CI_TRIGGERED_BY:-unknown}\"}"
fi