#!/bin/bash
# hooks/dispatcher.d/pre-tool-use/check-phase-alignment.sh
#
# Purpose: General phase alignment check for all commands

# Skip if already handled by specific validator
if [[ "$COMMAND" =~ "build-custom-llvm.sh" ]]; then
    exit 0
fi

# Only check for build/test commands
if [[ ! "$COMMAND" =~ (build|test|cargo|rustc|pytest) ]]; then
    exit 0
fi

echo "[$(date)] Checking phase alignment for: $COMMAND"

# Load current phase
PHASE_FILE="docs/ci-status/pipeline-log.json"
if [[ -f "$PHASE_FILE" ]]; then
    CURRENT_PHASE=$(jq -r '.current_phase.id // "unknown"' "$PHASE_FILE" 2>/dev/null || echo "unknown")
    echo "[$(date)] Current phase: $CURRENT_PHASE"
    
    # Emit metric
    if [[ -f "hooks/dispatcher.d/common/metrics.sh" ]]; then
        source hooks/dispatcher.d/common/metrics.sh
        emit_counter "phase.command" 1 "phase:${CURRENT_PHASE},command:${COMMAND//[^a-zA-Z0-9]/_}"
    fi
fi