#!/usr/bin/env bash
# setup-github-secrets.sh - Set up GitHub repository secrets
#
# Purpose: Configure GitHub secrets for CI/CD pipeline
# Usage: ./setup-github-secrets.sh
#
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== GitHub Secrets Setup ===${NC}"
echo

# Step 1: Check GitHub CLI installation
echo "Step 1: Checking GitHub CLI..."
if ! command -v gh &>/dev/null; then
    echo -e "${RED}✗ GitHub CLI not installed${NC}"
    echo "Please install with: brew install gh"
    exit 1
fi
echo -e "${GREEN}✓ GitHub CLI installed${NC} ($(gh --version | head -1))"
echo

# Step 2: Check authentication
echo "Step 2: Checking authentication..."
if ! gh auth status &>/dev/null; then
    echo -e "${YELLOW}⚠ Not authenticated with GitHub${NC}"
    echo
    echo "Please run: gh auth login"
    echo "Then re-run this script."
    exit 1
fi
echo -e "${GREEN}✓ Authenticated${NC}"
gh auth status
echo

# Step 3: Confirm repository
echo "Step 3: Confirming repository..."
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
if [[ -z "$REPO" ]]; then
    echo -e "${RED}✗ Not in a GitHub repository${NC}"
    echo "Please run this from the NeXTRust repository root"
    exit 1
fi
echo -e "${GREEN}✓ Repository: $REPO${NC}"
echo

# Step 4: Check existing secrets
echo "Step 4: Checking existing secrets..."
echo "Current secrets:"
gh secret list || echo "No secrets found"
echo

# Step 5: Set secrets
echo -e "${BLUE}Step 5: Setting up secrets...${NC}"
echo

# O3_ENDPOINT (non-sensitive, can be shown)
echo -e "${YELLOW}Setting O3_ENDPOINT...${NC}"
gh secret set O3_ENDPOINT --body "https://api.openai.com/v1"
echo -e "${GREEN}✓ O3_ENDPOINT set${NC}"
echo

# OPENAI_API_KEY (sensitive)
echo -e "${YELLOW}Setting OPENAI_API_KEY...${NC}"
echo "Please enter your OpenAI API key (starts with 'sk-'):"
echo "Note: The key will not be displayed as you type"
read -s OPENAI_KEY
echo

if [[ -z "$OPENAI_KEY" ]]; then
    echo -e "${RED}✗ No API key provided${NC}"
    exit 1
fi

if [[ ! "$OPENAI_KEY" =~ ^sk- ]]; then
    echo -e "${YELLOW}⚠ Warning: API key should start with 'sk-'${NC}"
    echo "Continue anyway? (y/N)"
    read -r confirm
    if [[ "$confirm" != "y" ]]; then
        exit 1
    fi
fi

echo "$OPENAI_KEY" | gh secret set OPENAI_API_KEY
echo -e "${GREEN}✓ OPENAI_API_KEY set${NC}"
echo

# Optional: GEMINI_API_KEY
echo -e "${YELLOW}Set GEMINI_API_KEY? (optional, for API fallback) [y/N]:${NC}"
read -r set_gemini
if [[ "$set_gemini" == "y" ]]; then
    echo "Please enter your Gemini API key:"
    read -s GEMINI_KEY
    echo
    if [[ -n "$GEMINI_KEY" ]]; then
        echo "$GEMINI_KEY" | gh secret set GEMINI_API_KEY
        echo -e "${GREEN}✓ GEMINI_API_KEY set${NC}"
    else
        echo -e "${YELLOW}⚠ Skipped GEMINI_API_KEY${NC}"
    fi
fi
echo

# Step 6: Verify
echo -e "${BLUE}Step 6: Verifying secrets...${NC}"
echo "Updated secrets list:"
gh secret list
echo

# Step 7: Test workflow
echo -e "${BLUE}Step 7: Testing integration...${NC}"
echo "Would you like to trigger a test workflow? (y/N):"
read -r test_workflow
if [[ "$test_workflow" == "y" ]]; then
    echo "Triggering test workflow..."
    gh workflow run nextrust-ci.yml || echo -e "${YELLOW}⚠ No test workflow found${NC}"
    echo
    echo "To monitor the workflow run:"
    echo "  gh run list --limit 1"
    echo "  gh run watch"
fi

echo
echo -e "${GREEN}✅ GitHub secrets setup complete!${NC}"
echo
echo "Next steps:"
echo "1. Verify secrets are working: ./ci/scripts/test-o3-integration.sh"
echo "2. Monitor costs: nextrust usage-report --days 7"
echo "3. Check workflow runs: gh run list"