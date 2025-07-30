#!/bin/bash
# hooks/dispatcher.d/post-tool-use/analyze-failure.sh
#
# Purpose: Handle build failures using common failure analysis

# Only proceed on failures
if [[ "$EXIT_CODE" == "0" ]]; then
    exit 0
fi

echo "[$(date)] Analyzing failure: $COMMAND (exit code: $EXIT_CODE)"

# Source common functions
source hooks/dispatcher.d/common/failure-tracking.sh
source hooks/dispatcher.d/common/failure-analysis.sh

# Source the failure tracking database
source hooks/dispatcher.d/common/failure-tracking-db.sh

# Increment failure count for this specific command
increment_failure_count_for_command "$COMMAND"

# Also increment commit-based failure count
increment_failure_count

# Emit failure metric
if command -v emit_counter &>/dev/null; then
    emit_counter "build.failures" 1 "command:${COMMAND//[^a-zA-Z0-9]/_},exit_code:${EXIT_CODE}"
fi

# Extract error output from payload
ERROR_OUTPUT=$(echo "$PAYLOAD" | jq -r '.tool_response.output // empty' 2>/dev/null | tail -100)

# Use unified failure analysis
analyze_failure "$COMMAND" "$EXIT_CODE" "$ERROR_OUTPUT"