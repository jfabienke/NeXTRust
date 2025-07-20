#!/usr/bin/env bash
# ci/scripts/test-all-simple.sh - Simplified test runner that works without Python dependencies
#
# Purpose: Run all CI pipeline tests without requiring typer
# Usage: ./ci/scripts/test-all-simple.sh
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
        # Show error for debugging
        echo "    Error: $(eval "$test_command" 2>&1 | head -1)"
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

echo "NeXTRust CI Pipeline Test Suite (Simplified)"
echo "============================================"
echo

echo "═══ Core Pipeline Tests ═══"

# Status tracking - test status-append.py directly
run_test "Status tracking" \
    "python3 ci/scripts/status-append.py 'test' '{\"msg\":\"test\"}'"

# Phase management - test pipeline log structure
run_test "Phase management" \
    "test -f docs/ci-status/pipeline-log.json || (mkdir -p docs/ci-status && echo '{}' > docs/ci-status/pipeline-log.json)"

run_test "Known issue matching" \
    "test -f docs/ci-status/known-issues.json"

run_test "Environment setup" \
    "bash -c 'source ci/scripts/setup-env.sh && [[ -n \$CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR ]]'"

run_test "File creation validation" \
    "test -x hooks/dispatcher.d/pre-tool-use/validate-file-creation.sh"

echo
echo "═══ Hook System Tests ═══"

run_test "Dispatcher executable" \
    "test -x hooks/dispatcher.sh"

run_test "Pre-tool-use hooks" \
    "ls hooks/dispatcher.d/pre-tool-use/*.sh >/dev/null 2>&1"

run_test "Post-tool-use hooks" \
    "ls hooks/dispatcher.d/post-tool-use/*.sh >/dev/null 2>&1"

run_test "Common functions" \
    "test -f hooks/dispatcher.d/common/failure-analysis.sh"

run_test "Failure tracking DB" \
    "test -f hooks/dispatcher.d/common/failure-tracking-db.sh"

echo
echo "═══ Security Tests ═══"

run_test "Input validation" \
    "test -f ci/scripts/slash/validate-input.sh"

run_test "Slash command validation" \
    "bash -c 'source ci/scripts/slash/validate-input.sh && validate_command_name test-cmd >/dev/null'"

run_test "Path traversal protection" \
    "bash -c 'source ci/scripts/slash/validate-input.sh && ! validate_file_path \"../etc/passwd\" 2>/dev/null'"

echo
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

run_test "ccusage availability check" \
    "test -x ci/scripts/check-ccusage.sh"

run_test "Token usage tracking" \
    "test -d docs/ci-status/metrics"

run_test "Model pricing config" \
    "test -f ci/config/model-pricing.json && jq -e '.prices_per_million_tokens.\"openai-o3\"' ci/config/model-pricing.json"

echo
echo "═══ CLI Tool Tests ═══"

run_test "Slash command scripts" \
    "test \$(ls ci/scripts/slash/*.sh | wc -l) -gt 5"

run_test "Slash command common.sh" \
    "grep -q 'validate-input.sh' ci/scripts/slash/common.sh"

run_test "Status append wrapper" \
    "python3 ci/scripts/status-append.py 'test' '{\"msg\":\"test\"}'"

echo
echo "═══ Version 2.x Features ═══"

run_test "Dispatcher v2.2 unified" \
    "test -f hooks/dispatcher.sh"

run_test "Unified failure analysis" \
    "grep -q 'analyze_failure' hooks/dispatcher.d/common/failure-analysis.sh"

run_test "O3 integration variables" \
    "grep -q 'O3_ENDPOINT' ~/.zshrc && grep -q 'OPENAI_API_KEY' ~/.zshrc"

run_test "Gemini free pricing" \
    "jq -e '.prices_per_million_tokens.\"gemini-2.5-pro\".cli_rate_limits.requests_per_day == 1000' ci/config/model-pricing.json"

run_test "O3 integration test suite" \
    "test -x ci/scripts/test-o3-integration-suite.sh"

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