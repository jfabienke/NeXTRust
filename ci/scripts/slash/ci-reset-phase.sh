#!/usr/bin/env bash
# ---
# argument-hint: "<phase-id>"
# ---
# ci/scripts/slash/ci-reset-phase.sh - Reset a phase for retry
#
# Purpose: Clear phase completion marker to allow phase to run again
# Usage: /ci-reset-phase <phase-id>
# Security: Validates phase ID pattern

source ci/scripts/slash/common.sh

# SECURITY: Validate phase ID using type-specific validation
PHASE_ID=$(validate_arg "${CI_ARGS:-}" 'phase_id' 'phase ID')

# Check write permission
check_write_permission

# Acquire lock for mutation
acquire_command_lock

# Verify phase exists in pipeline log
PIPELINE_LOG="docs/ci-status/pipeline-log.json"

if [[ ! -f "$PIPELINE_LOG" ]]; then
    post_error "No pipeline log found. Cannot verify phase."
    exit 1
fi

# Get current phase info
CURRENT_PHASE=$(jq -r '.current_phase.id // "unknown"' "$PIPELINE_LOG" 2>/dev/null)
PHASE_NAME=$(jq -r --arg id "$PHASE_ID" '.phases[]? | select(.id == $id) | .name // empty' "$PIPELINE_LOG" 2>/dev/null)

# If phase name not found in phases array, check current phase
if [[ -z "$PHASE_NAME" ]] && [[ "$CURRENT_PHASE" == "$PHASE_ID" ]]; then
    PHASE_NAME=$(jq -r '.current_phase.name // "Unknown"' "$PIPELINE_LOG" 2>/dev/null)
fi

if [[ -z "$PHASE_NAME" ]]; then
    # List available phases
    AVAILABLE_PHASES=$(cat << 'EOF'
• `phase-1` - Environment Setup
• `phase-2` - LLVM Backend Modifications
• `phase-3` - Rust Target Implementation
• `phase-4` - Emulation Testing
• `phase-5` - Standard Library Port
EOF
)
    
    post_error "Unknown phase: \`$PHASE_ID\`

**Available phases:**
$AVAILABLE_PHASES"
    exit 1
fi

# Check for phase completion marker
PHASE_MARKER="artifacts/phase/${PHASE_ID}.done"
MARKER_EXISTS=false

if [[ -f "$PHASE_MARKER" ]]; then
    MARKER_EXISTS=true
fi

# Update pipeline log to reset phase status
echo "[$(date)] Resetting phase $PHASE_ID in pipeline log..."

# Create a temporary file for the updated log
TMP_LOG="/tmp/pipeline-log-$$.json"

# Reset phase status in JSON
if jq --arg id "$PHASE_ID" '
    if .current_phase.id == $id then
        .current_phase.status = "pending"
    else . end' "$PIPELINE_LOG" > "$TMP_LOG"; then
    
    # Atomically update the log
    mv "$TMP_LOG" "$PIPELINE_LOG"
else
    rm -f "$TMP_LOG"
    post_error "Failed to update pipeline log"
    exit 1
fi

# Remove phase marker if it exists
if [[ "$MARKER_EXISTS" == "true" ]]; then
    rm -f "$PHASE_MARKER"
    MARKER_MSG="Phase marker removed."
else
    MARKER_MSG="No phase marker found."
fi

# Log the reset
if [[ -x "ci/scripts/status-append.py" ]]; then
    python3 ci/scripts/status-append.py "phase_reset" \
        "{\"phase\": \"$PHASE_ID\", \"name\": \"$PHASE_NAME\", \"reset_by\": \"${CI_TRIGGERED_BY:-unknown}\"}"
fi

RESPONSE="✅ Reset phase: **$PHASE_NAME** (\`$PHASE_ID\`)

**Status**: Ready to retry
**$MARKER_MSG**

The phase will run again on the next pipeline execution. You may want to:
1. Clear any backoff with \`/ci-clear-backoff\`
2. Trigger a new build by pushing a commit"

post_success "$RESPONSE"
log_command "success" "phase=$PHASE_ID"