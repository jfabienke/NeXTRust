#!/bin/bash
# ci/scripts/request-review.sh - Request implementation review from Gemini
#
# Purpose: Request code review when phase completes
# Usage: Called by dispatcher.sh on phase completion

set -euo pipefail

request_gemini_review() {
    # Check if artifacts exist
    if [[ ! -d "target/m68k-next-nextstep/release" ]]; then
        echo "No artifacts to review yet"
        return 0
    fi
    
    # Bundle artifacts (if they exist)
    local artifacts=""
    if ls target/m68k-next-nextstep/release/*.mach-o 2>/dev/null; then
        artifacts=$(tar czf - \
            target/m68k-next-nextstep/release/*.mach-o \
            test-results/*.log 2>/dev/null \
            docs/ci-status/pipeline-log.json | base64)
    fi
    
    # Prepare review request
    local request=$(cat <<EOF
{
  "phase": "$(jq -r .current_phase.id docs/ci-status/pipeline-log.json 2>/dev/null || echo 'unknown')",
  "changes": $(git diff --name-only HEAD~1 2>/dev/null | jq -R . | jq -s . || echo '[]'),
  "test_results": "$(jq .test_summary test-results/summary.json 2>/dev/null || echo '{}')",
  "artifacts_base64": "$artifacts"
}
EOF
)
    
    # Check if API is configured
    if [[ -z "${GEMINI_ENDPOINT:-}" ]] || [[ -z "${GEMINI_TOKEN:-}" ]]; then
        echo "Warning: Gemini API not configured, skipping review request"
        return 0
    fi
    
    # Call Gemini API
    echo "Requesting implementation review from Gemini..."
    response=$(curl -s -X POST "$GEMINI_ENDPOINT/review" \
        -H "Authorization: Bearer $GEMINI_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$request")
    
    # Update status using thread-safe helper
    python ci/scripts/status-append.py "gemini_review" \
        "{\"phase\": \"$(jq -r .current_phase.id docs/ci-status/pipeline-log.json 2>/dev/null || echo 'unknown')\", \"summary\": $(echo "$response" | jq -c .summary 2>/dev/null || echo '{}')}"
}

# Main execution
request_gemini_review