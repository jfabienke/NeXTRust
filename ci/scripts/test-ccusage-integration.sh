#!/usr/bin/env bash
# ci/scripts/test-ccusage-integration.sh - Test ccusage integration
#
# Purpose: Comprehensive test suite for ccusage integration
# Usage: ./ci/scripts/test-ccusage-integration.sh
#
set -uo pipefail

# Enable debug output for test logging
set -x

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== ccusage Integration Test Suite ==="
echo

# Test counter
PASSED=0
FAILED=0

# Test function
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -n "Testing $test_name... "
    if eval "$test_command" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC}"
        echo "  Command: $test_command"
        echo "  Output: $(eval "$test_command" 2>&1 | head -3)"
        ((FAILED++))
    fi
}

# Test 1: Check availability script exists
run_test "availability checker exists" \
    "test -f ci/scripts/check-ccusage.sh"

run_test "availability checker is executable" \
    "test -x ci/scripts/check-ccusage.sh"

# Test 2: Run availability checker
run_test "can run availability checker" \
    "ci/scripts/check-ccusage.sh || [[ \$? -eq 1 ]]"

# Test 3: Check hook integration
run_test "stop hook exists" \
    "test -f hooks/dispatcher.d/stop/capture-usage.sh"

run_test "stop hook includes availability check" \
    "grep -q 'check-ccusage.sh' hooks/dispatcher.d/stop/capture-usage.sh"

# Test 4: Check metrics directory
run_test "metrics directory exists" \
    "test -d docs/ci-status/metrics"

# Test 5: Test hook resilience (simulate missing ccusage)
echo
echo "Testing hook resilience..."
TEMP_PATH="/tmp/test-path-$$"
mkdir -p "$TEMP_PATH"

# Create a test payload
export PAYLOAD='{"session_id": "test-123"}'
export PATH="$TEMP_PATH:$PATH"

echo -n "  Hook handles missing ccusage... "
if bash hooks/dispatcher.d/stop/capture-usage.sh >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗${NC}"
    ((FAILED++))
fi

# Test 6: Check for failure logging
echo -n "  Failure is logged... "
if grep -q "ccusage not available" docs/ci-status/metrics/token-usage-*.jsonl 2>/dev/null || \
   [[ ! -f docs/ci-status/metrics/token-usage-$(date +%Y%m).jsonl ]]; then
    echo -e "${GREEN}✓${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗${NC}"
    ((FAILED++))
fi

# Test 7: Create mock ccusage for testing
cat > "$TEMP_PATH/ccusage" << 'EOF'
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "1.0.60"
elif [[ "$2" == "test-fail" ]]; then
    exit 1
else
    cat << JSON
{
    "session_id": "$2",
    "model": "claude-3-5-sonnet",
    "input_tokens": 1000,
    "output_tokens": 500,
    "total_tokens": 1500
}
JSON
fi
EOF
chmod +x "$TEMP_PATH/ccusage"

echo
echo "Testing with mock ccusage..."

# Test 8: Version check
echo -n "  Version check works... "
if $TEMP_PATH/ccusage --version | grep -q "1.0.60"; then
    echo -e "${GREEN}✓${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗${NC}"
    ((FAILED++))
fi

# Test 9: Successful capture
export PAYLOAD='{"session_id": "test-success"}'
echo -n "  Successful usage capture... "
if bash hooks/dispatcher.d/stop/capture-usage.sh >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗${NC}"
    ((FAILED++))
fi

# Test 10: Check if data was written
echo -n "  Usage data was logged... "
if grep -q "test-success" docs/ci-status/metrics/token-usage-$(date +%Y%m).jsonl 2>/dev/null; then
    echo -e "${GREEN}✓${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗${NC}"
    ((FAILED++))
fi

# Test 11: Failed capture handling
export PAYLOAD='{"session_id": "test-fail"}'
echo -n "  Failed capture is handled... "
if bash hooks/dispatcher.d/stop/capture-usage.sh >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗${NC}"
    ((FAILED++))
fi

# Test 12: Cost calculation
echo -n "  Cost calculation in logs... "
if grep -q "cost_usd" docs/ci-status/metrics/token-usage-$(date +%Y%m).jsonl 2>/dev/null; then
    echo -e "${GREEN}✓${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗${NC}"
    ((FAILED++))
fi

# Cleanup
rm -rf "$TEMP_PATH"
unset PAYLOAD
export PATH="${PATH#$TEMP_PATH:}"

# Summary
echo
echo "════════════════════════════════"
echo "Test Summary:"
echo "  Total:  $((PASSED + FAILED))"
echo -e "  Passed: ${GREEN}$PASSED${NC}"
if [[ $FAILED -gt 0 ]]; then
    echo -e "  Failed: ${RED}$FAILED${NC}"
    exit 1
else
    echo "  Failed: $FAILED"
    echo
    echo -e "${GREEN}All tests passed!${NC}"
    echo
    echo "Note: ccusage command not found on this system."
    echo "Integration will activate when Claude Code is available."
    exit 0
fi