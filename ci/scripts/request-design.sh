#!/bin/bash
# ci/scripts/request-design.sh - Request design decisions from o3
#
# Purpose: Escalate novel design challenges to o3 API
# Usage: Called when encountering unknown build issues

set -euo pipefail

request_o3_design() {
    local context=$1
    local error=$2
    
    # Check if we've seen this before
    if [[ -f "docs/ci-status/known-issues.json" ]]; then
        if jq -e --arg err "$error" '.known_issues[] | select(.error == $err)' docs/ci-status/known-issues.json >/dev/null; then
            echo "Known issue - applying standard fix"
            return 0
        fi
    fi
    
    # Prepare design request
    local request=$(cat <<EOF
{
  "context": "$context",
  "error": "$error", 
  "phase": "$(jq -r .current_phase.id docs/ci-status/pipeline-log.json 2>/dev/null || echo 'unknown')",
  "existing_attempts": $(jq --arg err "$error" '.activities | map(select(.details.error == $err)) | length' docs/ci-status/pipeline-log.json 2>/dev/null || echo 0)
}
EOF
)
    
    # Check if API is configured
    if [[ -z "${O3_ENDPOINT:-}" ]] || [[ -z "${O3_TOKEN:-}" ]]; then
        echo "Warning: O3 API not configured, skipping design request"
        return 0
    fi
    
    # Call o3 API
    echo "Requesting design decision from o3..."
    response=$(curl -s -X POST "$O3_ENDPOINT/design" \
        -H "Authorization: Bearer $O3_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$request")
    
    # Log decision using status-append.py for thread safety
    python3 ci/scripts/status-append.py "design_decision" \
        "{\"request\": $request, \"response\": $(echo "$response" | jq -c .)}"
}

# Main execution
if [[ $# -eq 2 ]]; then
    request_o3_design "$1" "$2"
else
    echo "Usage: request-design.sh <context> <error>"
    exit 1
fi