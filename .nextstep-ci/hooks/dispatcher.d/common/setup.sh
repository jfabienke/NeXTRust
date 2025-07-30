#!/bin/bash
# hooks/dispatcher.d/common/setup.sh - Common setup for all hooks
#
# Purpose: Initialize environment, parse payload, setup logging
# Exports: Common variables for use by all hook handlers

# Setup logging
export LOG_DIR=".claude/hook-logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
export LOG_FILE="$LOG_DIR/$(date +%Y%m%d-%H%M%S)-$HOOK_TYPE.log"

# Redirect output to log file while preserving console output
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "[$(date)] Hook dispatcher started: $HOOK_TYPE"

# Validate JSON payload
if ! echo "$PAYLOAD" | jq empty 2>/dev/null; then
    echo "[$(date)] Invalid JSON payload, exiting cleanly"
    exit 0
fi

# Parse payload fields
export TOOL_NAME=$(echo "$PAYLOAD" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
export COMMAND=$(echo "$PAYLOAD" | jq -r '.tool_args.command // empty' 2>/dev/null || echo "")
export EXIT_CODE=$(echo "$PAYLOAD" | jq -r '.tool_response.exit_code // 0' 2>/dev/null || echo "0")
export SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id' 2>/dev/null || echo "unknown")

# Environment variables
export RUNNER_NAME="${RUNNER_NAME:-local}"
export OS_NAME="${GITHUB_JOB:-${OS:-unknown}}"
export CPU_VARIANT="${CPU_VARIANT:-default}"
export COMMIT_SHA="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo "no-commit")}"
export RUN_ID="${GITHUB_RUN_ID:-local-$(date +%s)}"
export RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-1}"

# Timing
export HOOK_START_TIME=$SECONDS

# Debug mode
if [[ "${NEXTRUST_DEBUG:-0}" == "1" || "${HOOK_DEBUG:-0}" == "1" ]]; then
    echo "[DEBUG] Environment:"
    echo "  HOOK_TYPE=$HOOK_TYPE"
    echo "  TOOL_NAME=$TOOL_NAME"
    echo "  COMMAND=$COMMAND"
    echo "  EXIT_CODE=$EXIT_CODE"
    echo "  SESSION_ID=$SESSION_ID"
    echo "  RUNNER_NAME=$RUNNER_NAME"
    echo "  COMMIT_SHA=$COMMIT_SHA"
fi