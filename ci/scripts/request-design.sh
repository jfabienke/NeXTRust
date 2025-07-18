#!/usr/bin/env bash
# ci/scripts/request-design.sh - Wrapper for AI service design requests
#
# Purpose: Backward compatibility wrapper for O3 design requests
# Usage: ./ci/scripts/request-design.sh <context> [error]
#
set -uo pipefail

echo "[$(date)] Delegating to unified AI service handler..."

# Get arguments
CONTEXT="${1:-}"
ERROR="${2:-}"

# Build context string
if [[ -n "$ERROR" ]]; then
    FULL_CONTEXT="$CONTEXT|$ERROR"
else
    FULL_CONTEXT="$CONTEXT"
fi

# Call unified handler
exec ci/scripts/request-ai-service.sh --service o3 --type design --context "$FULL_CONTEXT"