#!/usr/bin/env bash
# ci/scripts/agent-feedback-loop.sh - Main agent orchestration loop
#
# Purpose: Run Claude Code with explicit configuration and retry logic
# Usage: ./ci/scripts/agent-feedback-loop.sh
#
set -uo pipefail

echo "=== Starting Agent Feedback Loop ==="
echo

# Configuration
CLAUDE_MD="CLAUDE.md"
MAX_RETRIES=3
RETRY_COUNT=0

# Validate Claude.md exists
if [[ ! -f "$CLAUDE_MD" ]]; then
    echo "Error: $CLAUDE_MD not found" >&2
    exit 1
fi

# Get current phase (with fallback if nextrust CLI doesn't exist)
if [[ -x "./ci/scripts/nextrust" ]]; then
    PHASE_ID=$(./ci/scripts/nextrust get-phase 2>/dev/null | grep "Phase ID:" | cut -d: -f2 | tr -d ' ' || echo "phase-2")
else
    # Default to phase 2 (LLVM build) if CLI not available
    PHASE_ID="phase-2"
fi
echo "Current phase: $PHASE_ID"

# Build the task prompt based on context
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    # In CI: Generate specific build task
    TASK=$(./ci/scripts/agent-ci-task.sh)
else
    # Local development: Use phase-based tasks
    case "$PHASE_ID" in
        "phase-2")
            TASK="Complete LLVM backend modifications for NeXTSTEP Mach-O support"
            ;;
        "phase-3")
            TASK="Implement Rust target specification for m68k-next-nextstep"
            ;;
        "phase-4")
            TASK="Set up and validate emulation testing infrastructure"
            ;;
        "phase-5")
            TASK="Integrate and test the CI pipeline"
            ;;
        *)
            TASK="Continue with the current development phase"
            ;;
    esac
fi

echo "Task: $TASK"
echo

# Check if claude command is available
if ! command -v claude &> /dev/null; then
    echo "Error: claude command not found. Please install Claude Code." >&2
    exit 1
fi

# Main execution with retry logic
echo "Invoking Claude Code with:"
echo "  - System prompt: $CLAUDE_MD"
echo "  - Retry with context: enabled"
echo "  - Max retries: $MAX_RETRIES"
echo

# Execute with new flags
if claude \
    --system-prompt "$CLAUDE_MD" \
    --retry-with-new-context \
    --non-interactive \
    -f "$TASK"; then
    
    echo
    echo "✅ Agent loop completed successfully"
    
    # Log success
    if [[ -x "./ci/scripts/nextrust" ]]; then
        ./ci/scripts/nextrust update-status \
            "Agent feedback loop completed" \
            --status-type success \
            --phase "$PHASE_ID"
    else
        python3 ci/scripts/status-append.py "agent_success" \
            '{"message": "Agent feedback loop completed", "phase": "'$PHASE_ID'"}'
    fi
    
    exit 0
else
    EXIT_CODE=$?
    echo
    echo "❌ Agent loop failed with exit code: $EXIT_CODE"
    
    # Log failure
    if [[ -x "./ci/scripts/nextrust" ]]; then
        ./ci/scripts/nextrust update-status \
            "Agent feedback loop failed after retries" \
            --status-type error \
            --phase "$PHASE_ID" \
            --metadata "{\"exit_code\": $EXIT_CODE, \"retries\": $MAX_RETRIES}"
    else
        python3 ci/scripts/status-append.py "agent_failure" \
            '{"message": "Agent feedback loop failed", "phase": "'$PHASE_ID'", "exit_code": '$EXIT_CODE', "retries": '$MAX_RETRIES'}'
    fi
    
    # Escalate to human
    if [[ -x "ci/scripts/escalate-to-human.sh" ]]; then
        ./ci/scripts/escalate-to-human.sh \
            "Agent loop failed after $MAX_RETRIES automatic retries. Exit code: $EXIT_CODE"
    fi
    
    exit $EXIT_CODE
fi