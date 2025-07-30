#!/bin/bash
# hooks/dispatcher.d/user-prompt-submit/phase-banner.sh
#
# Purpose: Add phase context banner to prompts
# Triggered by: UserPromptSubmit hook
#
set -euo pipefail

# Get current phase
PHASE_FILE="docs/ci-status/pipeline-log.json"
if [[ -f "$PHASE_FILE" ]]; then
    PHASE_ID=$(jq -r '.current_phase.id // "unknown"' "$PHASE_FILE" 2>/dev/null || echo "unknown")
else
    PHASE_ID="unknown"
fi

# Get current git SHA
PROJECT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "no-git")

# Extract prompt and CWD
PROMPT=$(echo "$PAYLOAD" | jq -r '.prompt // ""' 2>/dev/null || echo "")
CWD=$(echo "$PAYLOAD" | jq -r '.cwd // ""' 2>/dev/null || echo "")

# Output banner
echo "[Phase $PHASE_ID • $PROJECT_SHA] >"

# Log CWD for debugging
echo "[$(date)] Working directory: $CWD"

# Store CWD for other hooks
echo "$CWD" > .claude/current-cwd