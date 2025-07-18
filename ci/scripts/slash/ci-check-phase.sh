#!/usr/bin/env bash
# ---
# argument-hint: ""
# ---
# ci/scripts/slash/ci-check-phase.sh - Show current phase details
#
# Purpose: Display detailed information about the current CI phase
# Usage: /ci-check-phase

source ci/scripts/slash/common.sh

# Check if pipeline log exists
PIPELINE_LOG="docs/ci-status/pipeline-log.json"

if [[ ! -f "$PIPELINE_LOG" ]]; then
    post_error "No pipeline status found. The pipeline may not have run yet."
    exit 1
fi

# Extract phase information
PHASE_INFO=$(jq -r '.current_phase // empty' "$PIPELINE_LOG" 2>/dev/null)

if [[ -z "$PHASE_INFO" ]]; then
    post_error "Could not read phase information from pipeline log"
    exit 1
fi

# Parse phase details
PHASE_ID=$(echo "$PHASE_INFO" | jq -r '.id // "unknown"')
PHASE_NAME=$(echo "$PHASE_INFO" | jq -r '.name // "Unknown"')
PHASE_STATUS=$(echo "$PHASE_INFO" | jq -r '.status // "unknown"')

# Get expected files if available
EXPECTED_FILES=$(echo "$PHASE_INFO" | jq -r '.expected_files[]? // empty' 2>/dev/null)

# Count recent activities for this phase
RECENT_ACTIVITIES=$(jq -r --arg phase "$PHASE_ID" '
    .activities[-10:]? // [] | 
    map(select(.details.phase? == $phase or .type == "phase_*")) | 
    length' "$PIPELINE_LOG" 2>/dev/null || echo "0")

# Calculate phase progress (simplified)
case "$PHASE_ID" in
    "phase-1")
        TOTAL_STEPS=3
        ;;
    "phase-2")
        TOTAL_STEPS=5
        ;;
    "phase-3")
        TOTAL_STEPS=4
        ;;
    *)
        TOTAL_STEPS=1
        ;;
esac

# Build response
RESPONSE="## 🎯 Current Phase: $PHASE_NAME

**ID**: \`$PHASE_ID\`
**Status**: \`$PHASE_STATUS\`
**Recent Activities**: $RECENT_ACTIVITIES

### Expected Deliverables:"

if [[ -n "$EXPECTED_FILES" ]]; then
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            RESPONSE="$RESPONSE
✅ \`$file\`"
        else
            RESPONSE="$RESPONSE
⏳ \`$file\`"
        fi
    done <<< "$EXPECTED_FILES"
else
    RESPONSE="$RESPONSE
*No specific files tracked for this phase*"
fi

# Add phase-specific information
case "$PHASE_ID" in
    "phase-1")
        RESPONSE="$RESPONSE

### Phase Goals:
- Set up MCP configuration
- Initialize development environment
- Configure CI/CD pipeline"
        ;;
    "phase-2")
        RESPONSE="$RESPONSE

### Phase Goals:
- Implement LLVM Mach-O support
- Add m68k-next-nextstep triple
- Configure relocation handling"
        ;;
    "phase-3")
        RESPONSE="$RESPONSE

### Phase Goals:
- Define Rust target specification
- Implement atomic operations
- Build no_std hello world"
        ;;
esac

RESPONSE="$RESPONSE

---
*Use \`/ci-status\` for full pipeline status or \`/ci-reset-phase $PHASE_ID\` to retry this phase*"

# Post response
post_response "$RESPONSE"

# Log successful command
log_command "success"