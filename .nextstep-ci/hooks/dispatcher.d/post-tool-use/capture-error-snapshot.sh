#!/bin/bash
# hooks/dispatcher.d/post-tool-use/capture-error-snapshot.sh
#
# Purpose: Delegate to common failure analysis for file errors

# Only process if there was an error
EXIT_CODE=$(echo "$PAYLOAD" | jq -r '.tool_response.exit_code // 0' 2>/dev/null || echo "0")
if [[ "$EXIT_CODE" == "0" ]]; then
    exit 0
fi

# Source common failure analysis
source hooks/dispatcher.d/common/failure-analysis.sh

# Extract command and error output
COMMAND=$(echo "$PAYLOAD" | jq -r '.tool_args.command // ""' 2>/dev/null || echo "")
ERROR_OUTPUT=$(echo "$PAYLOAD" | jq -r '.tool_response.stderr // ""' 2>/dev/null || echo "")

# Check if this is a file-related error and capture snapshot
if is_file_error "$ERROR_OUTPUT"; then
    capture_error_snapshot "$COMMAND" "$ERROR_OUTPUT"
fi