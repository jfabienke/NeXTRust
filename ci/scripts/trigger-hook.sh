#!/usr/bin/env bash
# ci/scripts/trigger-hook.sh - Trigger hooks directly in CI
#
# Purpose: Simulate Claude Code hook triggers for CI environment
# Usage: ./ci/scripts/trigger-hook.sh <hook-type> <tool-name> <command> [exit-code]
#
set -uo pipefail

HOOK_TYPE="${1:-}"
TOOL_NAME="${2:-Bash}"
COMMAND="${3:-}"
EXIT_CODE="${4:-0}"
SESSION_ID="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"

if [[ -z "$HOOK_TYPE" || -z "$COMMAND" ]]; then
    echo "Usage: $0 <hook-type> <tool-name> <command> [exit-code]"
    exit 1
fi

# Generate hook payload
PAYLOAD=$(cat <<EOF
{
  "tool_name": "$TOOL_NAME",
  "tool_args": {
    "command": "$COMMAND"
  },
  "tool_response": {
    "exit_code": $EXIT_CODE
  },
  "session_id": "$SESSION_ID",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)

# Call the dispatcher
echo "$PAYLOAD" | ./hooks/dispatcher.sh "$HOOK_TYPE"