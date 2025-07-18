#!/bin/bash
# hooks/dispatcher-v2.sh - Modular hook dispatcher
#
# Purpose: Thin router that delegates to specialized scripts
# Inputs: Hook type ($1) and JSON payload (stdin)
# Outputs: Logs to .claude/hook-logs/, updates status artifacts
# Usage: Called automatically by Claude Code via settings.json

set -uo pipefail

# Note: CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1 ensures we're always in project root
# No need for manual cd commands

HOOK_TYPE=${1:-}

# Always log that dispatcher was called
echo "[$(date)] Hook dispatcher-v2 called with type: ${HOOK_TYPE:-none}"

# Check for slash command mode FIRST
if [[ -n "${CI_COMMAND:-}" ]]; then
    echo "[$(date)] Executing slash command: $CI_COMMAND"
    
    # Create directory for slash commands if needed
    mkdir -p ci/scripts/slash
    
    # Execute command script if exists
    COMMAND_SCRIPT="ci/scripts/slash/${CI_COMMAND}.sh"
    if [[ -f "$COMMAND_SCRIPT" && -x "$COMMAND_SCRIPT" ]]; then
        # Pass args safely with proper quoting
        "$COMMAND_SCRIPT" "${CI_ARGS:-}"
    else
        # Command not found - post error to PR
        if [[ -n "${CI_PR_NUMBER:-}" ]] && command -v gh &> /dev/null; then
            gh api repos/${GITHUB_REPOSITORY}/issues/${CI_PR_NUMBER}/comments \
                -f body="❌ Unknown command: \`$CI_COMMAND\`. Try \`/ci-help\` for available commands."
        fi
        echo "[ERROR] Unknown slash command: $CI_COMMAND"
        exit 1
    fi
    
    exit 0
fi

# Normal hook processing
export PAYLOAD=$(cat)  # JSON from Claude Code

# Validate hook type
if [[ -z "$HOOK_TYPE" ]]; then
    echo "[ERROR] No hook type provided"
    exit 0
fi

# Normalize hook type (handle both formats)
if [[ "$HOOK_TYPE" == "UserPromptSubmit" ]]; then
    HOOK_TYPE="user-prompt-submit"
elif [[ "$HOOK_TYPE" == "ToolOutput" ]]; then
    HOOK_TYPE="tool-output"
fi

# Setup base environment
if [[ -f "hooks/dispatcher.d/common/setup.sh" ]]; then
    source hooks/dispatcher.d/common/setup.sh
fi

# Route to appropriate handlers
HOOK_DIR="hooks/dispatcher.d/${HOOK_TYPE}"
if [[ -d "$HOOK_DIR" ]]; then
    for script in "$HOOK_DIR"/*.sh; do
        if [[ -f "$script" && -x "$script" ]]; then
            echo "[$(date)] Executing: $script"
            source "$script" || {
                echo "[$(date)] Warning: $script exited with code $?"
            }
        fi
    done
else
    echo "[$(date)] No handlers found for hook type: $HOOK_TYPE"
fi

# Cleanup and metrics
if [[ -f "hooks/dispatcher.d/common/cleanup.sh" ]]; then
    source hooks/dispatcher.d/common/cleanup.sh
fi

exit 0