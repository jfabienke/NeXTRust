#!/usr/bin/env bash
# Validate AI activation system components
set -euo pipefail

echo "🔍 AI Activation System Validation"
echo "=================================="

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validation counters
PASS=0
FAIL=0
WARN=0

# Check function
check() {
    local description="$1"
    local command="$2"
    local required="${3:-true}"
    
    printf "%-50s" "$description..."
    
    if eval "$command" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        ((PASS++))
    else
        if [[ "$required" == "true" ]]; then
            echo -e "${RED}✗${NC}"
            ((FAIL++))
        else
            echo -e "${YELLOW}⚠${NC}"
            ((WARN++))
        fi
    fi
}

echo -e "\n📁 Required Files"
echo "----------------"
check "PR review workflow" "test -f .github/workflows/pr-review.yml"
check "AI service handler" "test -x ci/scripts/request-ai-service.sh"
check "Budget monitor" "test -x ci/scripts/budget-monitor.py"
check "Metrics dashboard" "test -x ci/scripts/metrics-dashboard.py"
check "Gemini CLI wrapper" "test -x ci/scripts/gemini-cli-wrapper.sh"
check "Phase completion hook" "test -x hooks/dispatcher.d/common/90-phase-complete.sh"
check "AI review slash command" "test -x ci/scripts/slash/ci-ai-review.sh"
check "Design help slash command" "test -x ci/scripts/slash/ci-design-help.sh"
check "Model pricing config" "test -f ci/config/model-pricing.json"
check "Metrics emission module" "test -f hooks/dispatcher.d/common/metrics.sh"

echo -e "\n🔧 Configuration"
echo "---------------"
check "Metrics directory exists" "test -d docs/ci-status/metrics"
check "Usage directory exists" "test -d docs/ci-status/usage"
check "AI playbook documentation" "test -f docs/ai-activation-playbook.md"
check "OpenAI setup guide" "test -f docs/infrastructure/openai-setup.md"
check "Budget state directory" "test -d .claude || mkdir -p .claude"

echo -e "\n🌐 Environment (Optional)"
echo "------------------------"
check "GEMINI_API_KEY set" "test -n \"\${GEMINI_API_KEY:-}\"" false
check "OPENAI_API_KEY set" "test -n \"\${OPENAI_API_KEY:-}\"" false
check "O3_ENDPOINT set" "test -n \"\${O3_ENDPOINT:-}\"" false
check "GITHUB_TOKEN set" "test -n \"\${GITHUB_TOKEN:-}\"" false
check "STATSD_HOST set" "test -n \"\${STATSD_HOST:-}\"" false

echo -e "\n🛠️ Tools"
echo "--------"
check "Git installed" "command -v git"
check "Python3 installed" "command -v python3"
check "jq installed" "command -v jq"
check "GitHub CLI installed" "command -v gh" false
check "Gemini CLI installed" "command -v gemini" false

echo -e "\n📊 Summary"
echo "---------"
echo -e "Passed: ${GREEN}$PASS${NC}"
echo -e "Failed: ${RED}$FAIL${NC}"
echo -e "Warnings: ${YELLOW}$WARN${NC}"

if [[ $FAIL -eq 0 ]]; then
    echo -e "\n${GREEN}✅ AI activation system is ready for deployment!${NC}"
    exit 0
else
    echo -e "\n${RED}❌ $FAIL required components are missing${NC}"
    echo "Please review the checklist and ensure all components are in place."
    exit 1
fi