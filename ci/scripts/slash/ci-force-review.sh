#!/usr/bin/env bash
# ---
# argument-hint: "o3|gemini"
# ---
# ci/scripts/slash/ci-force-review.sh - Force immediate AI review
#
# Purpose: Trigger review by o3 or Gemini without waiting for phase completion
# Usage: /ci-force-review <o3|gemini>
# Security: Validates channel argument

source ci/scripts/slash/common.sh

# SECURITY: Validate review channel using type-specific validation
CHANNEL=$(validate_arg "${CI_ARGS:-}" 'review_channel' 'review channel')

# Check write permission
check_write_permission

# Acquire lock for mutation
acquire_command_lock

# Check if external APIs are enabled
if [[ "${SKIP_EXTERNAL_APIS:-0}" == "1" ]]; then
    post_error "External APIs are disabled in this environment. Cannot trigger review."
    exit 1
fi

# Get current phase and status
PIPELINE_LOG="docs/ci-status/pipeline-log.json"
if [[ -f "$PIPELINE_LOG" ]]; then
    CURRENT_PHASE=$(jq -r '.current_phase.id // "unknown"' "$PIPELINE_LOG" 2>/dev/null)
    PHASE_NAME=$(jq -r '.current_phase.name // "Unknown"' "$PIPELINE_LOG" 2>/dev/null)
else
    CURRENT_PHASE="unknown"
    PHASE_NAME="Unknown"
fi

echo "[$(date)] Triggering $CHANNEL review for phase $CURRENT_PHASE..."

# Call the appropriate review script
case "$CHANNEL" in
    "o3")
        REVIEW_SCRIPT="ci/scripts/request-design.sh"
        REVIEW_TYPE="design review"
        REVIEWER="OpenAI o3"
        ;;
    "gemini")
        REVIEW_SCRIPT="ci/scripts/request-review.sh"
        REVIEW_TYPE="implementation review"
        REVIEWER="Google Gemini"
        ;;
esac

# Check if review script exists
if [[ ! -x "$REVIEW_SCRIPT" ]]; then
    post_error "Review script not found: \`$REVIEW_SCRIPT\`. The review system may not be configured."
    exit 1
fi

# Prepare context for review
REVIEW_CONTEXT=$(cat << EOF
Triggered by: slash command (user: ${CI_TRIGGERED_BY:-unknown})
Phase: $PHASE_NAME ($CURRENT_PHASE)
Reason: Manual review request
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
)

# Export context for review script
export REVIEW_CONTEXT
export FORCE_REVIEW=1
export CI_PR_NUMBER="${CI_PR_NUMBER:-}"
export GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
export GITHUB_ACTIONS="${GITHUB_ACTIONS:-}"

# Execute review
echo "[$(date)] Calling $REVIEW_SCRIPT..."

if "$REVIEW_SCRIPT" 2>&1 | tee /tmp/review-output-$$; then
    # Extract any review ID or URL from output
    REVIEW_OUTPUT=$(cat /tmp/review-output-$$)
    REVIEW_ID=$(echo "$REVIEW_OUTPUT" | grep -oE 'review-[0-9a-f]{8}' | head -1 || echo "")
    
    RESPONSE="✅ Successfully triggered **$REVIEW_TYPE** by $REVIEWER

**Current Phase**: $PHASE_NAME (\`$CURRENT_PHASE\`)
**Review Type**: $REVIEW_TYPE"
    
    if [[ -n "$REVIEW_ID" ]]; then
        RESPONSE="$RESPONSE
**Review ID**: \`$REVIEW_ID\`"
    fi
    
    RESPONSE="$RESPONSE

The review is being processed. Results will be posted to the PR when complete.
This typically takes 2-5 minutes depending on the reviewer's queue."
    
    post_success "$RESPONSE"
    log_command "success" "channel=$CHANNEL,phase=$CURRENT_PHASE"
    
    # Log to status
    if [[ -x "ci/scripts/status-append.py" ]]; then
        python3 ci/scripts/status-append.py "review_triggered" \
            "{\"channel\": \"$CHANNEL\", \"phase\": \"$CURRENT_PHASE\", \"triggered_by\": \"${CI_TRIGGERED_BY:-unknown}\", \"review_id\": \"$REVIEW_ID\"}"
    fi
else
    ERROR_MSG=$(tail -5 /tmp/review-output-$$ 2>/dev/null | head -1)
    post_error "Failed to trigger $CHANNEL review. Error: $ERROR_MSG"
    log_command "failed" "channel=$CHANNEL,error=$ERROR_MSG"
    rm -f /tmp/review-output-$$
    exit 1
fi

rm -f /tmp/review-output-$$