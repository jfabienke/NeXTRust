#!/bin/bash
# hooks/dispatcher.d/post-tool-use/update-status.sh
#
# Purpose: Update pipeline status after command execution

echo "[$(date)] Updating pipeline status"

# Determine status type based on exit code
if [[ "$EXIT_CODE" == "0" ]]; then
    STATUS_TYPE="command_success"
else
    STATUS_TYPE="command_failure"
fi

# Create status data
STATUS_DATA=$(jq -n \
    --arg cmd "$COMMAND" \
    --arg exit "$EXIT_CODE" \
    --arg tool "$TOOL_NAME" \
    --arg matrix "${OS_NAME}-${RUST_PROFILE:-unknown}-${CPU_VARIANT}" \
    '{command: $cmd, exit_code: $exit, tool: $tool, matrix: $matrix}')

# Update status using thread-safe script
if [[ -x "ci/scripts/status-append.py" ]]; then
    python3 ci/scripts/status-append.py "$STATUS_TYPE" "$STATUS_DATA"
else
    echo "[$(date)] Warning: status-append.py not found or not executable"
fi

# Reset failure count on success
if [[ "$EXIT_CODE" == "0" ]]; then
    source hooks/dispatcher.d/common/failure-tracking.sh
    reset_failure_count
fi