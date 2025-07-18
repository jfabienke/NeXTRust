#!/usr/bin/env bash
# ci/scripts/request-review.sh - Wrapper for AI service review requests
#
# Purpose: Backward compatibility wrapper for Gemini review requests
# Usage: ./ci/scripts/request-review.sh
#
set -uo pipefail

echo "[$(date)] Delegating to unified AI service handler..."

# Get review context from environment or default
REVIEW_CONTEXT="${REVIEW_CONTEXT:-Phase completion review}"

# Call unified handler
exec ci/scripts/request-ai-service.sh --service gemini --type review --review-context "$REVIEW_CONTEXT"