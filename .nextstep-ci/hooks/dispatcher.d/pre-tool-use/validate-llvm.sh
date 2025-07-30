#!/bin/bash
# hooks/dispatcher.d/pre-tool-use/validate-llvm.sh
#
# Purpose: Validate LLVM build phase alignment

# Only proceed if this is an LLVM build command
if [[ ! "$COMMAND" =~ "build-custom-llvm.sh" ]]; then
    exit 0
fi

echo "[$(date)] Validating LLVM build phase alignment"

# Source common functions
source hooks/dispatcher.d/common/idempotency.sh
source hooks/dispatcher.d/common/failure-tracking.sh

# Check idempotency
if ! check_idempotency; then
    exit 0
fi

# Check failure limit
if ! check_failure_limit; then
    exit 1
fi

# Validate phase alignment
echo "[$(date)] Validating phase alignment..."

# Check if phase file exists
PHASE_FILE="docs/ci-status/pipeline-log.json"
if [[ ! -f "$PHASE_FILE" ]]; then
    echo "[$(date)] Warning: No phase file found, assuming phase 1"
else
    # Get current phase
    CURRENT_PHASE=$(jq -r '.current_phase.id // "phase-1"' "$PHASE_FILE" 2>/dev/null || echo "phase-1")
    echo "[$(date)] Current phase: $CURRENT_PHASE"
    
    # Validate LLVM build is appropriate for current phase
    if [[ "$CURRENT_PHASE" != "phase-2" ]] && [[ "$CURRENT_PHASE" != "phase-3" ]]; then
        echo "[$(date)] Warning: LLVM build in $CURRENT_PHASE (expected phase-2 or phase-3)"
    fi
fi

echo "[$(date)] Phase validation passed"

echo "[$(date)] LLVM build validation passed"