#!/usr/bin/env bash
# ci/scripts/test-o3-integration.sh - Test OpenAI O3 integration
#
# Purpose: Verify O3 API configuration and integration
# Usage: ./ci/scripts/test-o3-integration.sh
#
set -uo pipefail

# Enable debug output for test logging
set -x

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== OpenAI O3 Integration Test ==="
echo

# Test 1: Check environment variables
echo "Test 1: Checking environment variables..."
if [[ -z "${O3_ENDPOINT:-}" ]]; then
    echo -e "${RED}✗ O3_ENDPOINT not set${NC}"
    echo "  Set: export O3_ENDPOINT=\"https://api.openai.com/v1\""
    exit 1
else
    echo -e "${GREEN}✓ O3_ENDPOINT set:${NC} ${O3_ENDPOINT}"
fi

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    echo -e "${RED}✗ OPENAI_API_KEY not set${NC}"
    echo "  Set: export OPENAI_API_KEY=\"sk-...\""
    exit 1
else
    # Show only first 10 chars for security
    TOKEN_PREFIX=$(echo "$OPENAI_API_KEY" | head -c 10)
    echo -e "${GREEN}✓ OPENAI_API_KEY set:${NC} ${TOKEN_PREFIX}..."
fi

echo

# Test 2: Check API connectivity
echo "Test 2: Testing API connectivity..."

# Check if we're in test mode with fake keys
if [[ "$OPENAI_API_KEY" == "FAKE_OPENAI_KEY_FOR_TESTING" ]]; then
    echo -e "${YELLOW}⚠ Using test credentials - skipping actual API call${NC}"
    echo "  In production, this would check: $O3_ENDPOINT/models"
    RESPONSE="MOCK"
else
    echo "Checking $O3_ENDPOINT/models endpoint..."
    
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        "$O3_ENDPOINT/models" 2>/dev/null)

    if [[ "$RESPONSE" == "200" ]]; then
        echo -e "${GREEN}✓ API connection successful${NC}"
        
        # Show available models
        echo "Available models:"
        curl -s -H "Authorization: Bearer $OPENAI_API_KEY" \
            "$O3_ENDPOINT/models" 2>/dev/null | \
            jq -r '.data[].id' 2>/dev/null | grep -E "(gpt|o3)" | head -5 || true
    elif [[ "$RESPONSE" == "401" ]]; then
        echo -e "${RED}✗ Authentication failed (401)${NC}"
        echo "  Check your API key is valid"
        exit 1
    else
        echo -e "${RED}✗ API connection failed (HTTP $RESPONSE)${NC}"
        exit 1
    fi
fi

echo

# Test 3: Test request-ai-service.sh integration
echo "Test 3: Testing request-ai-service.sh integration..."
if [[ -f "ci/scripts/request-ai-service.sh" ]]; then
    # Create a test context
    TEST_CONTEXT="Integration test: Validate O3 pipeline integration"
    
    echo "Sending test design request..."
    if OUTPUT=$(./ci/scripts/request-ai-service.sh \
        --service o3 \
        --type design \
        --context "$TEST_CONTEXT" 2>&1); then
        
        if echo "$OUTPUT" | grep -q "Warning: O3 API not configured"; then
            echo -e "${YELLOW}⚠ O3 request was skipped (API not configured in pipeline)${NC}"
            echo "  This might be normal if running outside the pipeline context"
        else
            echo -e "${GREEN}✓ Design request completed successfully${NC}"
            echo "Response preview:"
            echo "$OUTPUT" | head -10
        fi
    else
        echo -e "${RED}✗ Design request failed${NC}"
        echo "Error output:"
        echo "$OUTPUT"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ request-ai-service.sh not found${NC}"
fi

echo

# Test 4: Check pricing configuration
echo "Test 4: Checking pricing configuration..."
if [[ -f "ci/config/model-pricing.json" ]]; then
    if jq -e '.prices_per_million_tokens."openai-o3"' ci/config/model-pricing.json >/dev/null 2>&1; then
        echo -e "${GREEN}✓ O3 pricing configured${NC}"
        jq '.prices_per_million_tokens."openai-o3"' ci/config/model-pricing.json
    else
        echo -e "${YELLOW}⚠ O3 pricing not found in model-pricing.json${NC}"
    fi
else
    echo -e "${YELLOW}⚠ model-pricing.json not found${NC}"
fi

echo

# Test 5: Simulate cost calculation
echo "Test 5: Cost estimation for sample request..."
# Typical design request: ~500 input + ~1000 output tokens
INPUT_TOKENS=500
OUTPUT_TOKENS=1000

if [[ -f "ci/config/model-pricing.json" ]]; then
    INPUT_PRICE=$(jq -r '.prices_per_million_tokens."openai-o3".input // 1.5' ci/config/model-pricing.json)
    OUTPUT_PRICE=$(jq -r '.prices_per_million_tokens."openai-o3".output // 6.0' ci/config/model-pricing.json)
    
    # Calculate costs (prices are per million tokens)
    INPUT_COST=$(echo "scale=4; $INPUT_TOKENS * $INPUT_PRICE / 1000000" | bc)
    OUTPUT_COST=$(echo "scale=4; $OUTPUT_TOKENS * $OUTPUT_PRICE / 1000000" | bc)
    TOTAL_COST=$(echo "scale=4; $INPUT_COST + $OUTPUT_COST" | bc)
    
    echo "Sample design request cost:"
    echo "  Input:  $INPUT_TOKENS tokens × \$$INPUT_PRICE/M = \$$INPUT_COST"
    echo "  Output: $OUTPUT_TOKENS tokens × \$$OUTPUT_PRICE/M = \$$OUTPUT_COST"
    echo -e "  ${GREEN}Total: \$$TOTAL_COST${NC}"
    
    # Monthly projection
    MONTHLY_REQUESTS=1000
    MONTHLY_COST=$(echo "scale=2; $TOTAL_COST * $MONTHLY_REQUESTS" | bc)
    echo -e "\nProjected monthly cost for $MONTHLY_REQUESTS requests: ${GREEN}\$$MONTHLY_COST${NC}"
fi

echo

# Summary
echo "=== Test Summary ==="
if [[ -n "${O3_ENDPOINT:-}" ]] && [[ -n "${OPENAI_API_KEY:-}" ]] && ([[ "$RESPONSE" == "200" ]] || [[ "$RESPONSE" == "MOCK" ]]); then
    if [[ "$RESPONSE" == "MOCK" ]]; then
        echo -e "${YELLOW}✓ O3 integration test completed (test mode)${NC}"
        echo
        echo "Note: Running with test credentials. For production testing:"
        echo "1. Set real OPENAI_API_KEY in local-test-secrets.env"
        echo "2. Set O3_ENDPOINT to actual OpenAI endpoint"
        echo "3. Re-run this test"
    else
        echo -e "${GREEN}✓ O3 integration is properly configured${NC}"
        echo
        echo "Next steps:"
        echo "1. Test in actual pipeline with real error scenarios"
        echo "2. Monitor usage via: nextrust usage-report --group-by model"
        echo "3. Set up GitHub secrets for CI/CD"
    fi
else
    echo -e "${RED}✗ O3 integration needs configuration${NC}"
    echo
    echo "Required steps:"
    echo "1. Set O3_ENDPOINT and OPENAI_API_KEY environment variables"
    echo "2. Verify API key is valid"
    echo "3. Re-run this test"
fi

echo
echo "For detailed setup instructions, see: docs/infrastructure/openai-setup.md"