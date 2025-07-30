#!/bin/bash
# hooks/dispatcher.d/post-tool-use/generate-success-artifacts.sh
#
# Purpose: Generate useful artifacts on successful operations
# Creates release notes, updates status boards, etc.
#
set -uo pipefail

# Only process successful commands
EXIT_CODE=$(echo "$PAYLOAD" | jq -r '.tool_response.exit_code // 1' 2>/dev/null || echo "1")
if [[ "$EXIT_CODE" != "0" ]]; then
    exit 0
fi

# Extract command details
COMMAND=$(echo "$PAYLOAD" | jq -r '.tool_args.command // ""' 2>/dev/null || echo "")
TOOL_NAME=$(echo "$PAYLOAD" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

echo "[$(date)] Processing successful command for artifact generation..."

# Function to generate build summary
generate_build_summary() {
    echo "[$(date)] Generating build summary..."
    
    local BUILD_SUMMARY_FILE="docs/ci-status/build-summaries/$(date +%Y%m%d-%H%M%S).json"
    mkdir -p "$(dirname "$BUILD_SUMMARY_FILE")"
    
    # Extract build information from output
    local OUTPUT=$(echo "$PAYLOAD" | jq -r '.tool_response.stdout // ""' 2>/dev/null)
    local BUILD_TIME="unknown"
    local ARTIFACTS=()
    
    # Try to extract build time
    if [[ "$OUTPUT" =~ Finished[[:space:]]+release[[:space:]]+\[optimized\][[:space:]]+target\(s\)[[:space:]]+in[[:space:]]+([0-9.]+s) ]]; then
        BUILD_TIME="${BASH_REMATCH[1]}"
    fi
    
    # Create summary
    cat > "$BUILD_SUMMARY_FILE" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "command": "$COMMAND",
  "build_time": "$BUILD_TIME",
  "phase": "${PHASE_ID:-unknown}",
  "success": true,
  "artifacts": []
}
EOF
    
    # Update project status board
    if [[ -f "docs/project-status.md" ]]; then
        echo "[$(date)] Updating project status board..."
        # This would update a markdown status board
        # For now, just log the update
        if command -v python3 &>/dev/null && [[ -x "ci/scripts/status-append.py" || -x "$(which status-append.py 2>/dev/null)" ]]; then
            python3 ci/scripts/status-append.py "build_success" \
                "{\"summary_file\": \"$BUILD_SUMMARY_FILE\", \"build_time\": \"$BUILD_TIME\"}" 2>/dev/null || true
        fi
    fi
}

# Function to generate test report
generate_test_report() {
    echo "[$(date)] Generating test report..."
    
    local TEST_REPORT_FILE="docs/ci-status/test-reports/$(date +%Y%m%d-%H%M%S).json"
    mkdir -p "$(dirname "$TEST_REPORT_FILE")"
    
    # Extract test statistics from output
    local OUTPUT=$(echo "$PAYLOAD" | jq -r '.tool_response.stdout // ""' 2>/dev/null)
    local TESTS_PASSED=0
    local TESTS_FAILED=0
    local TESTS_IGNORED=0
    
    # Parse test output (Rust format)
    if [[ "$OUTPUT" =~ test[[:space:]]+result:[[:space:]]+ok.[[:space:]]+([0-9]+)[[:space:]]+passed ]]; then
        TESTS_PASSED="${BASH_REMATCH[1]}"
    fi
    
    # Create report
    cat > "$TEST_REPORT_FILE" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "command": "$COMMAND",
  "phase": "${PHASE_ID:-unknown}",
  "results": {
    "passed": $TESTS_PASSED,
    "failed": $TESTS_FAILED,
    "ignored": $TESTS_IGNORED
  },
  "success": true
}
EOF
    
    # Log the report
    if command -v python3 &>/dev/null && [[ -x "ci/scripts/status-append.py" || -x "$(which status-append.py 2>/dev/null)" ]]; then
        python3 ci/scripts/status-append.py "test_success" \
            "{\"report_file\": \"$TEST_REPORT_FILE\", \"passed\": $TESTS_PASSED}" 2>/dev/null || true
    fi
}

# Function to generate release notes
generate_release_notes() {
    echo "[$(date)] Generating draft release notes..."
    
    local RELEASE_NOTES_FILE="docs/releases/draft-$(date +%Y%m%d-%H%M%S).md"
    mkdir -p "$(dirname "$RELEASE_NOTES_FILE")"
    
    # Get recent commits for release notes
    local COMMITS=$(git log --oneline -10 --pretty=format:"- %s (%h)")
    
    # Create draft release notes
    cat > "$RELEASE_NOTES_FILE" << EOF
# Release Notes - Draft

Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Recent Changes

$COMMITS

## Build Information

- Phase: ${PHASE_ID:-unknown}
- Command: $COMMAND
- Status: Success

## Next Steps

1. Review and edit these release notes
2. Add breaking changes section if applicable
3. Update version numbers
4. Create GitHub release

---
*This is an automatically generated draft. Please review and edit before publishing.*
EOF
    
    echo "[$(date)] Draft release notes saved to: $RELEASE_NOTES_FILE"
    
    # Log the generation
    if command -v python3 &>/dev/null && [[ -x "ci/scripts/status-append.py" || -x "$(which status-append.py 2>/dev/null)" ]]; then
        python3 ci/scripts/status-append.py "release_notes_draft" \
            "{\"file\": \"$RELEASE_NOTES_FILE\"}" 2>/dev/null || true
    fi
}

# Handle different types of successful operations
case "$COMMAND" in
    *"cargo build"*|*"build-custom-llvm"*)
        # Build success - generate build summary
        generate_build_summary
        ;;
        
    *"cargo test"*|*"run-emulator-tests"*)
        # Test success - generate test report
        generate_test_report
        ;;
        
    *"git tag"*|*"git push"*"--tags"*)
        # Tag/release - generate release notes
        generate_release_notes
        ;;
esac