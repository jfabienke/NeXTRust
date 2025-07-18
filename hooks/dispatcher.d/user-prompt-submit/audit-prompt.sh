#!/bin/bash
# hooks/dispatcher.d/user-prompt-submit/audit-prompt.sh
#
# Purpose: Audit all submitted prompts for traceability
# Triggered by: UserPromptSubmit hook
#
set -euo pipefail

# Extract prompt and metadata
PROMPT=$(echo "$PAYLOAD" | jq -r '.prompt // ""' 2>/dev/null || echo "")
CWD=$(echo "$PAYLOAD" | jq -r '.cwd // ""' 2>/dev/null || echo "")
SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")

# Get current phase
PHASE_FILE="docs/ci-status/pipeline-log.json"
if [[ -f "$PHASE_FILE" ]]; then
    PHASE_ID=$(jq -r '.current_phase.id // "unknown"' "$PHASE_FILE" 2>/dev/null || echo "unknown")
else
    PHASE_ID="unknown"
fi

# Calculate prompt metrics
PROMPT_LENGTH=${#PROMPT}
PROMPT_WORDS=$(echo "$PROMPT" | wc -w | tr -d ' ')
ESTIMATED_TOKENS=$((PROMPT_LENGTH / 4))  # Rough estimate

# Detect command type
COMMAND_TYPE="general"
if [[ "$PROMPT" =~ ^(ls|cd|pwd|echo) ]]; then
    COMMAND_TYPE="navigation"
elif [[ "$PROMPT" =~ (build|compile|cargo|make) ]]; then
    COMMAND_TYPE="build"
elif [[ "$PROMPT" =~ (test|check|verify) ]]; then
    COMMAND_TYPE="test"
elif [[ "$PROMPT" =~ (git|commit|push|pull) ]]; then
    COMMAND_TYPE="vcs"
fi

# Get environment info
RUNNER_NAME="${RUNNER_NAME:-local}"
CI_CONTEXT="${GITHUB_ACTIONS:-false}"

# Create enriched audit entry
AUDIT_ENTRY=$(jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg prompt "$PROMPT" \
    --arg phase "$PHASE_ID" \
    --arg cwd "$CWD" \
    --arg session "$SESSION_ID" \
    --arg user "${USER:-unknown}" \
    --arg cmd_type "$COMMAND_TYPE" \
    --arg runner "$RUNNER_NAME" \
    --arg ci "$CI_CONTEXT" \
    --argjson length "$PROMPT_LENGTH" \
    --argjson words "$PROMPT_WORDS" \
    --argjson tokens "$ESTIMATED_TOKENS" \
    '{
        timestamp: $timestamp,
        prompt: $prompt,
        phase: $phase,
        cwd: $cwd,
        session_id: $session,
        user: $user,
        metadata: {
            command_type: $cmd_type,
            prompt_metrics: {
                length: $length,
                words: $words,
                estimated_tokens: $tokens,
                actual_tokens: null,
                estimation_accuracy: null
            },
            environment: {
                runner: $runner,
                is_ci: ($ci == "true")
            }
        }
    }')

# Append to prompt log
if command -v python3 &>/dev/null && [[ -x "ci/scripts/status-append.py" || -x "$(which status-append.py 2>/dev/null)" ]]; then
    python3 ci/scripts/status-append.py "user_prompt" "$AUDIT_ENTRY" 2>/dev/null || true
fi

echo "[$(date)] Prompt audited"