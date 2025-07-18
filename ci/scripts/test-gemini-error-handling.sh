#!/usr/bin/env bash
# ci/scripts/test-gemini-error-handling.sh - Test Gemini error handling
#
# Purpose: Verify robust error handling for Gemini CLI integration
# Usage: ./ci/scripts/test-gemini-error-handling.sh
#
set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Gemini Error Handling Test Suite ==="
echo

# Source the error handler and wrapper functions
source ci/scripts/gemini-error-handler.sh
source ci/scripts/gemini-cli-wrapper.sh

# Test 1: Error parsing
echo "Test 1: Error message parsing..."
test_errors=(
    "Error: User not authenticated. Please run 'gemini auth' to log in.|AUTH_ERROR"
    "Error: Rate limit exceeded. Please try again later.|RATE_LIMIT"
    "Error: Network connection timeout|NETWORK_ERROR"
    "Error: Invalid input format|INVALID_INPUT"
    "Some random error|UNKNOWN_ERROR"
)

passed=0
failed=0

for test_case in "${test_errors[@]}"; do
    IFS='|' read -r error_msg expected_type <<< "$test_case"
    result=$(parse_gemini_error "$error_msg")
    
    if [[ "$result" == "$expected_type" ]]; then
        echo -e "  ${GREEN}✓${NC} Correctly identified: $expected_type"
        ((passed++))
    else
        echo -e "  ${RED}✗${NC} Failed: Expected $expected_type, got $result"
        echo "     Error message: $error_msg"
        ((failed++))
    fi
done

echo

# Test 2: Fallback handler
echo "Test 2: Fallback handler..."
temp_prompt="/tmp/test-prompt-$$"
echo "Test prompt" > "$temp_prompt"

# Test with no API key
unset GEMINI_API_KEY
if gemini_fallback_handler "$temp_prompt" "test" >/dev/null 2>&1; then
    echo -e "  ${RED}✗${NC} Fallback should fail without API key"
    ((failed++))
else
    echo -e "  ${GREEN}✓${NC} Correctly failed without API key"
    ((passed++))
fi

# Test with API key
export GEMINI_API_KEY="test-key"
if gemini_fallback_handler "$temp_prompt" "test" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Fallback suggests API usage with key"
    ((passed++))
else
    echo -e "  ${RED}✗${NC} Fallback should suggest API with key"
    ((failed++))
fi

rm -f "$temp_prompt"
echo

# Test 3: Usage logging
echo "Test 3: Usage logging..."
log_dir="docs/ci-status/metrics"
log_file="$log_dir/gemini-usage.jsonl"

# Note initial count
mkdir -p "$log_dir"
initial_count=$(wc -l < "$log_file" 2>/dev/null || echo 0)

# Log test entries
log_gemini_usage "1000" "5000" "true" ""
log_gemini_usage "2000" "0" "false" "RATE_LIMIT"

# Check log entries were added
final_count=$(wc -l < "$log_file")
added_count=$((final_count - initial_count))

if [[ $added_count -eq 2 ]]; then
    echo -e "  ${GREEN}✓${NC} Usage logging works (added 2 entries)"
    ((passed++))
    
    # Verify JSON format - check last 2 lines
    if tail -2 "$log_file" | jq -e . >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} New log entries are valid JSON"
        ((passed++))
    else
        echo -e "  ${RED}✗${NC} New log entries are not valid JSON"
        ((failed++))
    fi
else
    echo -e "  ${RED}✗${NC} Expected 2 new log entries, added $added_count"
    ((failed++))
fi

echo

# Test 4: Prompt size checking
echo "Test 4: Prompt size validation..."
small_file="/tmp/small-prompt-$$"
large_file="/tmp/large-prompt-$$"

# Create small file
echo "Small prompt" > "$small_file"

# Create large file (>800KB to exceed 200K token estimate)
dd if=/dev/zero bs=1024 count=850 2>/dev/null | tr '\0' 'a' > "$large_file"

if check_prompt_size "$small_file" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Small prompt passes size check"
    ((passed++))
else
    echo -e "  ${RED}✗${NC} Small prompt should pass size check"
    ((failed++))
fi

if check_prompt_size "$large_file" >/dev/null 2>&1; then
    echo -e "  ${RED}✗${NC} Large prompt should fail size check"
    ((failed++))
else
    echo -e "  ${GREEN}✓${NC} Large prompt correctly flagged"
    ((passed++))
fi

rm -f "$small_file" "$large_file"
echo

# Test 5: Integration with wrapper
echo "Test 5: Wrapper integration..."
if [[ -f "ci/scripts/gemini-cli-wrapper.sh" ]]; then
    if grep -q "gemini-error-handler.sh" ci/scripts/gemini-cli-wrapper.sh; then
        echo -e "  ${GREEN}✓${NC} Wrapper sources error handler"
        ((passed++))
    else
        echo -e "  ${RED}✗${NC} Wrapper doesn't source error handler"
        ((failed++))
    fi
    
    if grep -q "execute_gemini_with_retry" ci/scripts/gemini-cli-wrapper.sh; then
        echo -e "  ${GREEN}✓${NC} Wrapper uses retry function"
        ((passed++))
    else
        echo -e "  ${RED}✗${NC} Wrapper doesn't use retry function"
        ((failed++))
    fi
else
    echo -e "  ${YELLOW}⚠${NC} Wrapper not found"
fi

echo

# Summary
echo "════════════════════════════════"
echo "Test Summary:"
echo "  Total:  $((passed + failed))"
echo -e "  Passed: ${GREEN}$passed${NC}"
if [[ $failed -gt 0 ]]; then
    echo -e "  Failed: ${RED}$failed${NC}"
    exit 1
else
    echo "  Failed: $failed"
    echo
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi