#!/usr/bin/env bash
# ci/scripts/test-all.sh - Unified test runner for CI pipeline
#
# Purpose: Run all CI pipeline tests in organized test suites
# Usage: ./ci/scripts/test-all.sh [suite_name]
#
set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Test suite definitions (bash 3.x compatible)
test_suite_names() {
    echo "core hooks integration tools v2"
}

test_suite_desc() {
    case "$1" in
        core) echo "Core pipeline functionality" ;;
        hooks) echo "Hook system and dispatcher" ;;
        integration) echo "Integration with AI services" ;;
        tools) echo "CLI tools and utilities" ;;
        v2) echo "Version 2.x features" ;;
    esac
}

# Test functions
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -n "  Running $test_name... "
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if eval "$test_command" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo -e "${RED}✗${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

skip_test() {
    local test_name="$1"
    local reason="$2"
    
    echo -e "  Skipping $test_name... ${YELLOW}⚠${NC} ($reason)"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
}

# Core pipeline tests
test_suite_core() {
    echo "═══ Core Pipeline Tests ═══"
    
    run_test "Status tracking" \
        "python3 ci/scripts/tools/nextrust_cli.py update-status 'test' --status-type info"
    
    run_test "Phase management" \
        "python3 ci/scripts/tools/nextrust_cli.py set-phase test-phase 'Test Phase'"
    
    run_test "Known issue matching" \
        "test -f docs/ci-status/known-issues.json"
    
    run_test "Environment setup" \
        "bash -c 'source ci/scripts/setup-env.sh && [[ -n \$CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR ]]'"
    
    run_test "File creation validation" \
        "test -x hooks/dispatcher.d/pre-tool-use/validate-file-creation.sh"
}

# Hook system tests
test_suite_hooks() {
    echo "═══ Hook System Tests ═══"
    
    run_test "Dispatcher executable" \
        "test -x hooks/dispatcher.sh"
    
    run_test "Pre-tool-use hooks" \
        "ls hooks/dispatcher.d/pre-tool-use/*.sh >/dev/null 2>&1"
    
    run_test "Post-tool-use hooks" \
        "ls hooks/dispatcher.d/post-tool-use/*.sh >/dev/null 2>&1"
    
    run_test "Common functions" \
        "test -f hooks/dispatcher.d/common/failure-analysis.sh"
    
    # Test specific hook functionality
    local TEST_PAYLOAD='{"tool_name":"Bash","tool_args":{"command":"echo test"}}'
    run_test "Hook routing" \
        "echo '$TEST_PAYLOAD' | bash hooks/dispatcher.sh pre 2>/dev/null"
}

# Integration tests
test_suite_integration() {
    echo "═══ Integration Tests ═══"
    
    if command -v gemini &>/dev/null; then
        run_test "Gemini CLI integration" \
            "test -f GEMINI.md"
    else
        skip_test "Gemini CLI integration" "gemini not installed"
    fi
    
    run_test "AI service request handler" \
        "test -x ci/scripts/request-ai-service.sh"
    
    run_test "ccusage integration" \
        "test -f hooks/dispatcher.d/stop/capture-usage.sh"
    
    run_test "Token usage tracking" \
        "test -d docs/ci-status/metrics"
}

# Tool tests
test_suite_tools() {
    echo "═══ CLI Tool Tests ═══"
    
    if python3 -c "import typer" 2>/dev/null; then
        run_test "nextrust CLI basic" \
            "python3 ci/scripts/tools/nextrust_cli.py --help"
        
        run_test "nextrust version" \
            "python3 ci/scripts/tools/nextrust_cli.py version"
        
        run_test "nextrust tips" \
            "python3 ci/scripts/tools/nextrust_cli.py tips | grep -q 'NeXTRust CI Tips'"
        
        run_test "Status append wrapper" \
            "python3 ci/scripts/status-append.py 'test' '{\"msg\":\"test\"}'"
    else
        skip_test "nextrust CLI" "typer not installed"
    fi
    
    run_test "Slash command scripts" \
        "ls ci/scripts/slash/*.sh | wc -l | grep -qE '^[0-9]+$'"
}

# Version 2.x feature tests
test_suite_v2() {
    echo "═══ Version 2.x Features ═══"
    
    run_test "Dispatcher v2" \
        "test -f hooks/dispatcher-v2.sh"
    
    run_test "Unified failure analysis" \
        "grep -q 'analyze_failure' hooks/dispatcher.d/common/failure-analysis.sh"
    
    run_test "Model pricing config" \
        "test -f ci/config/model-pricing.json"
    
    # Test summarizer metrics
    local LARGE_OUTPUT=$(printf 'Test line %.0s\n' {1..1000})
    local PAYLOAD=$(jq -n --arg stdout "$LARGE_OUTPUT" '{
        tool_name: "Bash",
        tool_response: { stdout: $stdout }
    }')
    
    run_test "Build log summarizer" \
        "PAYLOAD='$PAYLOAD' bash hooks/dispatcher.d/tool-output/summarize-build-logs.sh 2>/dev/null"
}

# Main execution
main() {
    local suite="${1:-all}"
    
    echo "NeXTRust CI Pipeline Test Suite"
    echo "================================"
    echo
    
    if [[ "$suite" == "all" ]]; then
        # Run all test suites
        for suite_name in $(test_suite_names); do
            echo
            test_suite_$suite_name
        done
    else
        # Check if suite exists
        local suite_desc=$(test_suite_desc "$suite")
        if [[ -n "$suite_desc" ]]; then
            # Run specific suite
            echo "Running suite: $suite_desc"
            echo
            test_suite_$suite
        else
            echo "Unknown test suite: $suite"
            echo "Available suites:"
            for name in $(test_suite_names); do
                echo "  $name - $(test_suite_desc $name)"
            done
            exit 1
        fi
    fi
    
    # Summary
    echo
    echo "════════════════════════════════"
    echo "Test Summary:"
    echo "  Total:   $TOTAL_TESTS"
    echo -e "  Passed:  ${GREEN}$PASSED_TESTS${NC}"
    if [[ $FAILED_TESTS -gt 0 ]]; then
        echo -e "  Failed:  ${RED}$FAILED_TESTS${NC}"
    else
        echo "  Failed:  $FAILED_TESTS"
    fi
    if [[ $SKIPPED_TESTS -gt 0 ]]; then
        echo -e "  Skipped: ${YELLOW}$SKIPPED_TESTS${NC}"
    fi
    
    # Exit code
    if [[ $FAILED_TESTS -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run main
main "$@"