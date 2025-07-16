#!/bin/bash
# hooks/dispatcher.sh - Intelligent hook dispatcher
#
# Purpose: Routes Claude Code hooks to appropriate handlers based on context
# Inputs: Hook type ($1) and JSON payload (stdin)
# Outputs: Logs to .claude/hook-logs/, updates status artifacts
# Usage: Called automatically by Claude Code via settings.json

set -euo pipefail  # Exit on error, undefined vars, pipe failures

HOOK_TYPE=$1
PAYLOAD=$(cat)  # JSON from Claude Code

# Setup logging
LOG_DIR=".claude/hook-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y%m%d-%H%M%S)-$HOOK_TYPE.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "[$(date)] Hook dispatcher started: $HOOK_TYPE"

# Extract relevant fields
TOOL_NAME=$(echo "$PAYLOAD" | jq -r '.tool_name // empty')
COMMAND=$(echo "$PAYLOAD" | jq -r '.tool_args.command // empty')
EXIT_CODE=$(echo "$PAYLOAD" | jq -r '.tool_response.exit_code // 0')
SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id')

# Idempotency check with runner-specific session files
RUNNER_NAME="${RUNNER_NAME:-local}"
OS_NAME="${GITHUB_JOB:-${OS:-unknown}}"
CPU_VARIANT="${CPU_VARIANT:-default}"
SESSION_DIR=".claude/sessions"
SESSION_FILE="$SESSION_DIR/$RUNNER_NAME-$OS_NAME-$CPU_VARIANT.session"

mkdir -p "$SESSION_DIR"
LAST_SESSION=$(cat "$SESSION_FILE" 2>/dev/null || echo "")
if [[ "$SESSION_ID" == "$LAST_SESSION" ]]; then
    echo "[$(date)] Skipping duplicate session: $SESSION_ID"
    exit 0  # Already processed this session
fi

# Failure loop protection
COMMIT_SHA=$(git rev-parse HEAD)
BACKOFF_FILE=".claude/backoff/$COMMIT_SHA"
if [[ -f "$BACKOFF_FILE" ]]; then
    FAILURE_COUNT=$(cat "$BACKOFF_FILE")
    if [[ "$FAILURE_COUNT" -ge 3 ]]; then
        echo "::error::Commit $COMMIT_SHA has failed $FAILURE_COUNT times. Push new commit to retry."
        exit 1
    fi
fi

case "$HOOK_TYPE" in
    pre)
        # PreToolUse: Validate phase alignment
        if [[ "$COMMAND" =~ "build-custom-llvm.sh" ]]; then
            ./ci/scripts/validate-phase.sh || exit 1
        fi
        ;;
        
    post)
        # PostToolUse: Handle failures
        if [[ "$EXIT_CODE" != "0" ]]; then
            # Increment failure count for this commit
            mkdir -p .claude/backoff
            FAILURE_COUNT=$(cat "$BACKOFF_FILE" 2>/dev/null || echo "0")
            echo $((FAILURE_COUNT + 1)) > "$BACKOFF_FILE"
            
            ./ci/scripts/analyze-failure.sh "$COMMAND" "$EXIT_CODE"
        fi
        ;;
        
    stop)
        # Stop: Trigger reviews if phase complete
        CURRENT_PHASE=$(jq -r .current_phase.id docs/ci-status/pipeline-log.json 2>/dev/null || echo "unknown")
        PHASE_MARKER="artifacts/phase/$CURRENT_PHASE.done"
        
        if [[ -f "$PHASE_MARKER" ]]; then
            ./ci/scripts/request-review.sh
            rm "$PHASE_MARKER"
        fi
        ;;
esac

echo "$SESSION_ID" > "$SESSION_FILE"