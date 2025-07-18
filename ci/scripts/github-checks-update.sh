#!/bin/bash
# ci/scripts/github-checks-update.sh - Update GitHub Checks status
#
# Purpose: Update GitHub check runs with build status
# Usage: github-checks-update.sh --status <status> --phase <phase> --matrix <matrix> --conclusion <conclusion>

set -euo pipefail

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --status)
            STATUS="$2"
            shift 2
            ;;
        --phase)
            PHASE="$2"
            shift 2
            ;;
        --matrix)
            MATRIX="$2"
            shift 2
            ;;
        --conclusion|--outcome)  # Support both for backwards compatibility
            CONCLUSION="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

update_check() {
    local status=$STATUS
    local phase=$PHASE
    local conclusion=${CONCLUSION:-neutral}
    
    # Check if gh CLI is available
    if ! command -v gh &> /dev/null; then
        echo "Warning: gh CLI not found, skipping GitHub Checks update"
        return 0
    fi
    
    # Update GitHub check
    echo "Updating GitHub Check: Phase=$phase, Status=$status, Conclusion=$conclusion"
    
    gh api \
        --method POST \
        -H "Accept: application/vnd.github+json" \
        /repos/$GITHUB_REPOSITORY/check-runs \
        -f name="NeXTRust Phase: $phase ($MATRIX)" \
        -f head_sha=$GITHUB_SHA \
        -f status=$status \
        -f conclusion=$conclusion \
        -f output="{\"title\":\"Build Matrix: $MATRIX\",\"summary\":\"Phase: $phase, Status: $status\"}" \
        2>/dev/null || echo "Warning: Failed to update GitHub Check"
}

# Main execution
if [[ -n "${GITHUB_REPOSITORY:-}" ]] && [[ -n "${GITHUB_SHA:-}" ]]; then
    update_check
else
    echo "Not running in GitHub Actions environment, skipping check update"
fi