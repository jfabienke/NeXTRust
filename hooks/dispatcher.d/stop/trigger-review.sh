#!/bin/bash
# hooks/dispatcher.d/stop/trigger-review.sh
#
# Purpose: Trigger reviews when phase completes

echo "[$(date)] Checking for phase completion"

# Check current phase
PHASE_FILE="docs/ci-status/pipeline-log.json"
if [[ ! -f "$PHASE_FILE" ]]; then
    echo "[$(date)] No pipeline status file found"
    exit 0
fi

CURRENT_PHASE=$(jq -r '.current_phase.id // "unknown"' "$PHASE_FILE" 2>/dev/null || echo "unknown")
PHASE_STATUS=$(jq -r '.current_phase.status // "unknown"' "$PHASE_FILE" 2>/dev/null || echo "unknown")

echo "[$(date)] Current phase: $CURRENT_PHASE (status: $PHASE_STATUS)"

# Check for phase completion marker
PHASE_MARKER="artifacts/phase/${CURRENT_PHASE}.done"
if [[ ! -f "$PHASE_MARKER" ]]; then
    echo "[$(date)] Phase not yet complete"
    exit 0
fi

echo "[$(date)] Phase $CURRENT_PHASE complete, triggering review"

# Request review
if [[ -x "ci/scripts/request-review.sh" ]]; then
    ./ci/scripts/request-review.sh
    
    # Remove marker after review request
    rm -f "$PHASE_MARKER"
    
    # Emit metric
    if [[ -f "hooks/dispatcher.d/common/metrics.sh" ]]; then
        source hooks/dispatcher.d/common/metrics.sh
        emit_counter "phase.completed" 1 "phase:${CURRENT_PHASE}"
    fi
else
    echo "[$(date)] Warning: request-review.sh not found or not executable"
fi