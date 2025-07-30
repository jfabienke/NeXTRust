#!/bin/bash
# hooks/dispatcher.d/pre-tool-use/validate-cwd.sh
#
# Purpose: Enforce CWD policies based on current phase
# Uses: $CCODE_CWD environment variable from Claude Code 1.0.54
#
set -euo pipefail

# Skip if CCODE_CWD not available (pre-1.0.54)
if [[ -z "${CCODE_CWD:-}" ]]; then
    echo "[$(date)] CWD validation skipped (CCODE_CWD not available)"
    exit 0
fi

# Get current phase
PHASE_FILE="docs/ci-status/pipeline-log.json"
if [[ ! -f "$PHASE_FILE" ]]; then
    echo "[$(date)] No phase file found, skipping CWD validation"
    exit 0
fi

CURRENT_PHASE=$(jq -r '.current_phase.id // "unknown"' "$PHASE_FILE" 2>/dev/null || echo "unknown")

# Extract command being run
COMMAND=$(echo "$PAYLOAD" | jq -r '.tool_args.command // ""' 2>/dev/null || echo "")

# Define phase-specific CWD policies
case "$CURRENT_PHASE" in
    "phase-3")
        # Rust target development must be in rust/ directory
        if [[ "$COMMAND" =~ cargo|rustc|rustup ]] && [[ ! "$CCODE_CWD" =~ /rust/?$ ]]; then
            echo "::error::Phase 3 requires working in the rust/ directory"
            echo "::error::Current directory: $CCODE_CWD"
            echo "::error::Please run: cd rust/"
            exit 1
        fi
        ;;
        
    "phase-4")
        # Emulation testing must be in emulator/ directory
        if [[ "$COMMAND" =~ emulator|previous|qemu ]] && [[ ! "$CCODE_CWD" =~ /emulator/?$ ]]; then
            echo "::error::Phase 4 requires working in the emulator/ directory"
            echo "::error::Current directory: $CCODE_CWD"
            echo "::error::Please run: cd emulator/"
            exit 1
        fi
        ;;
        
    "phase-2")
        # LLVM work typically in patches/ or build/
        if [[ "$COMMAND" =~ llvm|clang|cmake ]] && [[ ! "$CCODE_CWD" =~ /(patches|build)/?$ ]]; then
            echo "::warning::Phase 2 LLVM work typically happens in patches/ or build/"
            echo "::warning::Current directory: $CCODE_CWD"
        fi
        ;;
esac

echo "[$(date)] CWD validation passed for phase $CURRENT_PHASE"