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
CLAUDE_MD="docs/ai/CLAUDE.md"
MAX_RETRIES=3
RETRY_COUNT=0

# Validate Claude.md exists
if [[ ! -f "$CLAUDE_MD" ]]; then
    echo "Error: $CLAUDE_MD not found" >&2
    exit 1
fi

# Get current phase
PHASE_ID=$(./ci/scripts/nextrust get-phase 2>/dev/null | grep "Phase ID:" | cut -d: -f2 | tr -d ' ' || echo "unknown")
echo "Current phase: $PHASE_ID"

# Build the task prompt based on phase
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
    ./ci/scripts/nextrust update-status \
        "Agent feedback loop completed" \
        --status-type success \
        --phase "$PHASE_ID"
    
    exit 0
else
    EXIT_CODE=$?
    echo
    echo "❌ Agent loop failed with exit code: $EXIT_CODE"
    
    # Log failure
    ./ci/scripts/nextrust update-status \
        "Agent feedback loop failed after retries" \
        --status-type error \
        --phase "$PHASE_ID" \
        --metadata "{\"exit_code\": $EXIT_CODE, \"retries\": $MAX_RETRIES}"
    
    # Escalate to human
    if [[ -x "ci/scripts/escalate-to-human.sh" ]]; then
        ./ci/scripts/escalate-to-human.sh \
            "Agent loop failed after $MAX_RETRIES automatic retries. Exit code: $EXIT_CODE"
    fi
    
    exit $EXIT_CODE
fi