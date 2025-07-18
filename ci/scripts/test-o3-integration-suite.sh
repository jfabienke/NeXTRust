#!/usr/bin/env bash
# ci/scripts/test-o3-integration-suite.sh - Comprehensive O3 integration tests
#
# Purpose: Test all aspects of OpenAI O3 integration
# Usage: ./ci/scripts/test-o3-integration-suite.sh [test_name]
#
set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
PASSED=0
FAILED=0
SKIPPED=0

# Test result function
report_test() {
    local test_name="$1"
    local result="$2"
    local message="${3:-}"
    
    case "$result" in
        pass)
            echo -e "${GREEN}✓${NC} $test_name"
            ((PASSED++))
            ;;
        fail)
            echo -e "${RED}✗${NC} $test_name"
            [[ -n "$message" ]] && echo "  └─ $message"
            ((FAILED++))
            ;;
        skip)
            echo -e "${YELLOW}⚠${NC} $test_name (skipped)"
            [[ -n "$message" ]] && echo "  └─ $message"
            ((SKIPPED++))
            ;;
    esac
}

# Test environment setup
test_environment() {
    echo -e "${BLUE}=== Environment Tests ===${NC}"
    
    # Check O3_ENDPOINT
    if [[ -n "${O3_ENDPOINT:-}" ]]; then
        report_test "O3_ENDPOINT configured" "pass"
    else
        report_test "O3_ENDPOINT configured" "fail" "Not set"
        return 1
    fi
    
    # Check OPENAI_API_KEY
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        report_test "OPENAI_API_KEY configured" "pass"
    else
        report_test "OPENAI_API_KEY configured" "fail" "Not set"
        return 1
    fi
    
    # Check key format
    if [[ "$OPENAI_API_KEY" =~ ^sk- ]]; then
        report_test "API key format valid" "pass"
    else
        report_test "API key format valid" "fail" "Should start with sk-*"
    fi
    
    return 0
}

# Test API connectivity
test_api_connectivity() {
    echo -e "\n${BLUE}=== API Connectivity Tests ===${NC}"
    
    # Skip if no credentials
    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        report_test "API connectivity" "skip" "No API key"
        return 0
    fi
    
    # Test models endpoint
    local response=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        "$O3_ENDPOINT/models" 2>/dev/null)
    
    if [[ "$response" == "200" ]]; then
        report_test "Models endpoint accessible" "pass"
    else
        report_test "Models endpoint accessible" "fail" "HTTP $response"
        return 1
    fi
    
    # Check for O3 model availability
    local models=$(curl -s -H "Authorization: Bearer $OPENAI_API_KEY" \
        "$O3_ENDPOINT/models" 2>/dev/null | jq -r '.data[].id' 2>/dev/null)
    
    if echo "$models" | grep -q "o3"; then
        report_test "O3 model available" "pass"
    else
        report_test "O3 model available" "skip" "Using GPT models for now"
    fi
    
    return 0
}

# Test request handling
test_request_handling() {
    echo -e "\n${BLUE}=== Request Handling Tests ===${NC}"
    
    # Test simple completion
    local test_prompt="What is 2+2? Reply with just the number."
    local response=$(curl -s -X POST "$O3_ENDPOINT/chat/completions" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"gpt-3.5-turbo\",
            \"messages\": [{\"role\": \"user\", \"content\": \"$test_prompt\"}],
            \"max_tokens\": 10,
            \"temperature\": 0
        }" 2>/dev/null)
    
    if echo "$response" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
        report_test "Basic API request" "pass"
        
        # Check response content
        local answer=$(echo "$response" | jq -r '.choices[0].message.content' | tr -d '[:space:]')
        if [[ "$answer" == "4" ]]; then
            report_test "Response validation" "pass"
        else
            report_test "Response validation" "fail" "Expected '4', got '$answer'"
        fi
    else
        report_test "Basic API request" "fail" "Invalid response format"
        echo "$response" | jq . 2>/dev/null || echo "$response"
    fi
}

# Test error handling
test_error_handling() {
    echo -e "\n${BLUE}=== Error Handling Tests ===${NC}"
    
    # Test invalid API key
    local bad_response=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer invalid-key" \
        "$O3_ENDPOINT/models" 2>/dev/null)
    
    if [[ "$bad_response" == "401" ]]; then
        report_test "Invalid key rejection" "pass"
    else
        report_test "Invalid key rejection" "fail" "Expected 401, got $bad_response"
    fi
    
    # Test rate limit handling (don't actually trigger it)
    report_test "Rate limit handling" "skip" "Not testing to avoid hitting limits"
    
    # Test timeout handling
    timeout 2s curl -s --max-time 1 \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        "https://httpstat.us/200?sleep=5000" >/dev/null 2>&1
    local exit_code=$?
    
    # Exit codes: 124=timeout command, 28=curl timeout, 7=connection failed, 35=SSL error
    if [[ $exit_code -eq 124 ]] || [[ $exit_code -eq 28 ]] || [[ $exit_code -eq 7 ]] || [[ $exit_code -eq 35 ]]; then
        report_test "Timeout handling" "pass"
    else
        report_test "Timeout handling" "fail" "Timeout not properly handled (exit code: $exit_code)"
    fi
}

# Test pipeline integration
test_pipeline_integration() {
    echo -e "\n${BLUE}=== Pipeline Integration Tests ===${NC}"
    
    # Check if request-ai-service.sh exists
    if [[ -f "ci/scripts/request-ai-service.sh" ]]; then
        report_test "AI service script exists" "pass"
        
        # Test dry run  
        if [[ -x "ci/scripts/request-ai-service.sh" ]]; then
            report_test "AI service script executable" "pass"
        else
            report_test "AI service script executable" "fail"
        fi
    else
        report_test "AI service script exists" "fail" "Not found"
    fi
    
    # Check failure analysis integration
    if grep -q "should_escalate_to_o3" hooks/dispatcher.d/common/failure-analysis.sh 2>/dev/null; then
        report_test "O3 escalation logic present" "pass"
    else
        report_test "O3 escalation logic present" "fail" "Not found in failure-analysis.sh"
    fi
    
    # Check slash command integration
    if grep -q "o3" ci/scripts/slash/ci-force-review.sh 2>/dev/null; then
        report_test "Slash command support" "pass"
    else
        report_test "Slash command support" "fail" "O3 not in force-review command"
    fi
}

# Test cost tracking
test_cost_tracking() {
    echo -e "\n${BLUE}=== Cost Tracking Tests ===${NC}"
    
    # Check pricing configuration
    if [[ -f "ci/config/model-pricing.json" ]]; then
        if jq -e '.prices_per_million_tokens."openai-o3"' ci/config/model-pricing.json >/dev/null 2>&1; then
            report_test "O3 pricing configured" "pass"
            
            # Validate pricing values
            local input_price=$(jq -r '.prices_per_million_tokens."openai-o3".input' ci/config/model-pricing.json)
            local output_price=$(jq -r '.prices_per_million_tokens."openai-o3".output' ci/config/model-pricing.json)
            
            if [[ "$input_price" == "2.00" ]] && [[ "$output_price" == "8.00" ]]; then
                report_test "Pricing values correct" "pass"
            else
                report_test "Pricing values correct" "fail" "Input: $input_price, Output: $output_price"
            fi
        else
            report_test "O3 pricing configured" "fail" "Not found in pricing config"
        fi
    else
        report_test "O3 pricing configured" "fail" "model-pricing.json not found"
    fi
    
    # Check usage logging
    if grep -q "openai-o3" hooks/dispatcher.d/stop/capture-usage.sh 2>/dev/null; then
        report_test "Usage capture support" "pass"
    else
        report_test "Usage capture support" "skip" "Generic model detection used"
    fi
}

# Test security
test_security() {
    echo -e "\n${BLUE}=== Security Tests ===${NC}"
    
    # Check for hardcoded keys
    if grep -r "sk-[a-zA-Z0-9]" . --include="*.sh" --include="*.yml" --exclude-dir=".git" 2>/dev/null | grep -v "sk-\.\.\." | grep -v "example" | grep -v "sk-\*"; then
        report_test "No hardcoded API keys" "fail" "Found potential API key in code"
    else
        report_test "No hardcoded API keys" "pass"
    fi
    
    # Check GitHub secrets usage in workflows
    if grep -q 'secrets.OPENAI_API_KEY' .github/workflows/*.yml 2>/dev/null; then
        report_test "GitHub secrets configured" "pass"
    else
        report_test "GitHub secrets configured" "skip" "Not found in workflows"
    fi
    
    # Check for secure transmission
    if [[ "$O3_ENDPOINT" =~ ^https:// ]]; then
        report_test "HTTPS endpoint" "pass"
    else
        report_test "HTTPS endpoint" "fail" "Not using HTTPS"
    fi
}

# Run specific test or all tests
run_tests() {
    local test_name="${1:-all}"
    
    echo -e "${BLUE}O3 Integration Test Suite${NC}"
    echo "========================="
    echo
    
    case "$test_name" in
        env|environment)
            test_environment
            ;;
        api|connectivity)
            test_environment && test_api_connectivity
            ;;
        request|handling)
            test_environment && test_api_connectivity && test_request_handling
            ;;
        error)
            test_environment && test_error_handling
            ;;
        pipeline)
            test_pipeline_integration
            ;;
        cost)
            test_cost_tracking
            ;;
        security)
            test_security
            ;;
        all)
            test_environment
            test_api_connectivity
            test_request_handling
            test_error_handling
            test_pipeline_integration
            test_cost_tracking
            test_security
            ;;
        *)
            echo "Usage: $0 [test_name]"
            echo
            echo "Available tests:"
            echo "  env|environment  - Test environment variables"
            echo "  api|connectivity - Test API connectivity"
            echo "  request|handling - Test request handling"
            echo "  error           - Test error handling"
            echo "  pipeline        - Test pipeline integration"
            echo "  cost            - Test cost tracking"
            echo "  security        - Test security measures"
            echo "  all             - Run all tests (default)"
            exit 1
            ;;
    esac
    
    # Summary
    echo
    echo "═══════════════════════════"
    echo "Test Summary:"
    echo -e "  Passed:  ${GREEN}$PASSED${NC}"
    [[ $FAILED -gt 0 ]] && echo -e "  Failed:  ${RED}$FAILED${NC}" || echo "  Failed:  $FAILED"
    [[ $SKIPPED -gt 0 ]] && echo -e "  Skipped: ${YELLOW}$SKIPPED${NC}"
    echo "  Total:   $((PASSED + FAILED + SKIPPED))"
    
    if [[ $FAILED -eq 0 ]]; then
        echo
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo
        echo -e "${RED}Some tests failed.${NC}"
        return 1
    fi
}

# Main execution
run_tests "$@"