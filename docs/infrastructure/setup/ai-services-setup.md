# AI Services Setup Guide

Last updated: 2025-07-18 16:15

## Overview

This guide covers setting up AI service integrations for the NeXTRust CI/CD pipeline, including OpenAI O3 for design decisions and Gemini 2.5 Pro for code reviews. With O3's recent 10x cost reduction and Gemini's free CLI tier, both services are now economically viable for regular use.

## Table of Contents

1. [Service Comparison](#service-comparison)
2. [OpenAI O3 Setup](#openai-o3-setup)
3. [Gemini CLI Setup](#gemini-cli-setup)
4. [GitHub Actions Configuration](#github-actions-configuration)
5. [Security Best Practices](#security-best-practices)
6. [Testing & Validation](#testing--validation)
7. [Cost Management](#cost-management)
8. [Troubleshooting](#troubleshooting)

## Service Comparison

| Feature | OpenAI O3 | Gemini 2.5 Pro |
|---------|-----------|----------------|
| **Primary Use** | Design decisions, complex architecture | Code reviews, implementation feedback |
| **Pricing** | $2/M input, $8/M output | FREE via CLI (1000/day limit) |
| **Rate Limits** | Tier-based | 60 requests/minute (CLI) |
| **Integration** | API only | CLI preferred, API available |
| **Best For** | Complex reasoning tasks | Regular code reviews |

## OpenAI O3 Setup

### Prerequisites

- OpenAI account with API access
- Billing enabled on your OpenAI account
- Understanding of API key security

### Obtaining API Keys

1. **Create/Login to OpenAI Account**
   - Visit [platform.openai.com](https://platform.openai.com)
   - Sign up or log in to your account

2. **Generate API Key**
   - Navigate to API Keys section
   - Click "Create new secret key"
   - Name it descriptively (e.g., "NeXTRust-O3-Dev")
   - Copy the key immediately (won't be shown again)

3. **Set Usage Limits** (Recommended)
   - Go to Usage Limits
   - Set monthly spend limit ($50-100 recommended)
   - Enable alerts at 80% usage

### Local Development Setup

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
# OpenAI API Configuration for O3 design decisions
export O3_ENDPOINT="https://api.openai.com/v1"
export OPENAI_API_KEY="sk-..."  # Your actual API key
```

Reload and verify:

```bash
source ~/.zshrc
echo $O3_ENDPOINT
echo $OPENAI_API_KEY | head -c 10  # Show only first 10 chars

# Test integration
./ci/scripts/test-o3-integration.sh
```

## Gemini CLI Setup

### Installation

1. **Install via npm** (requires Node.js 20+):
   ```bash
   npm install -g @google/gemini-cli
   ```

2. **First-time setup**:
   ```bash
   gemini
   # Follow prompts to:
   # - Choose color theme
   # - Authenticate with Google account
   ```

3. **Verify installation**:
   ```bash
   gemini --version
   # Should show 0.1.12 or higher
   ```

### Configuration

The Gemini CLI provides:
- 1000 free requests per day
- 60 requests per minute rate limit
- No API key needed (uses OAuth)

For CI/CD fallback, you can optionally set:
```bash
export GEMINI_API_KEY="your-api-key"  # Optional, for API fallback
```

## GitHub Actions Configuration

### Adding Repository Secrets

#### Via GitHub Web Interface

1. Navigate to repository settings:
   ```
   https://github.com/[your-username]/NeXTRust/settings/secrets/actions
   ```

2. Add O3 endpoint:
   - Click "New repository secret"
   - Name: `O3_ENDPOINT`
   - Value: `https://api.openai.com/v1`
   - Click "Add secret"

3. Add OpenAI API key:
   - Click "New repository secret"
   - Name: `OPENAI_API_KEY`
   - Value: Your OpenAI API key
   - Click "Add secret"

4. (Optional) Add Gemini API key for fallback:
   - Name: `GEMINI_API_KEY`
   - Value: Your Google AI API key

#### Via GitHub CLI

```bash
# Set O3_ENDPOINT
gh secret set O3_ENDPOINT --body "https://api.openai.com/v1"

# Set OPENAI_API_KEY (prompts for secure input)
gh secret set OPENAI_API_KEY

# Optional: Set GEMINI_API_KEY
gh secret set GEMINI_API_KEY
```

### Workflow Configuration

Ensure your workflows reference these secrets:

```yaml
env:
  O3_ENDPOINT: ${{ secrets.O3_ENDPOINT }}
  OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
  GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}  # Optional
```

## Security Best Practices

### API Key Management

1. **Separate Keys by Environment**:
   - Development: Personal keys in ~/.zshrc
   - CI/CD: Service account keys in GitHub secrets
   - Production: Separate production keys

2. **Regular Rotation** (Set calendar reminders):
   - Rotate keys every 3 months
   - Update all references
   - Revoke old keys
   - Test after rotation

3. **Access Control**:
   - Limit key permissions where possible
   - Use different keys for different services
   - Monitor usage patterns

### Environment Isolation

Using direnv for project-specific variables:

```bash
# .envrc (git-ignored)
export OPENAI_API_KEY="sk-dev-..."
export GEMINI_API_KEY="aiza-dev-..."

# For CI testing
# .envrc.ci (git-ignored)
export OPENAI_API_KEY="sk-ci-..."
```

### Audit and Monitoring

1. **Check OpenAI usage**:
   ```bash
   # Via dashboard or API
   curl -H "Authorization: Bearer $OPENAI_API_KEY" \
     "$O3_ENDPOINT/usage"
   ```

2. **Monitor Gemini usage**:
   ```bash
   # Check daily count
   grep "gemini" docs/ci-status/metrics/gemini-usage.jsonl | wc -l
   ```

3. **Cost tracking**:
   ```bash
   nextrust usage-report --days 7 --group-by model
   ```

## Testing & Validation

### OpenAI O3 Tests

1. **Basic connectivity**:
   ```bash
   curl -s -H "Authorization: Bearer $OPENAI_API_KEY" \
     "$O3_ENDPOINT/models" | jq '.data[].id' | grep -q o3
   ```

2. **Integration test**:
   ```bash
   ./ci/scripts/test-o3-integration.sh
   ```

3. **Manual design request**:
   ```bash
   ./ci/scripts/request-ai-service.sh \
     --service o3 \
     --type design \
     --context "Test: Architecture for error handling"
   ```

### Gemini CLI Tests

1. **Health check**:
   ```bash
   gemini "What is 2+2?"
   ```

2. **Error handling test**:
   ```bash
   ./ci/scripts/test-gemini-error-handling.sh
   ```

3. **Review simulation**:
   ```bash
   echo "Test code review" > /tmp/test.md
   ./ci/scripts/request-ai-service.sh \
     --service gemini \
     --type review
   ```

### CI/CD Validation

1. **Trigger test workflow**:
   ```bash
   gh workflow run test-ai-services.yml
   ```

2. **Check slash commands**:
   ```
   /ci-force-review o3
   /ci-force-review gemini
   ```

## Cost Management

### Current Pricing

#### OpenAI O3
- Input: $2.00 per million tokens
- Output: $8.00 per million tokens
- Cached Input: $1.50 per million tokens
- Average request: ~$0.009 (500 input + 1000 output tokens)

#### Gemini 2.5 Pro
- CLI: **FREE** (1000 requests/day, 60/minute)
- API: $1.25/M input, $10.00/M output
- Recommendation: Use CLI whenever possible

### Budget Guidelines

| Service | Use Case | Monthly Budget |
|---------|----------|----------------|
| O3 | Design decisions | $50-100 |
| Gemini CLI | Code reviews | $0 (free tier) |
| Gemini API | Overflow/backup | $20-50 |

### Cost Controls

1. **Set spending limits** in provider dashboards
2. **Monitor via pipeline**:
   ```bash
   # Daily cost check
   ./ci/scripts/monitor-costs.sh day
   
   # Model-specific costs
   grep "openai-o3" docs/ci-status/metrics/token-usage-*.jsonl | \
     jq -s 'map(.cost_usd.total) | add'
   ```

3. **Implement circuit breakers**:
   - Automatic escalation limits
   - Daily/hourly caps
   - Alert on unusual spikes

## Troubleshooting

### Common Issues

#### Environment Variables Not Set
```bash
# Debug
env | grep -E "(O3|OPENAI|GEMINI)"

# Fix
source ~/.zshrc
```

#### Authentication Errors (401)
- Verify API key is correct
- Check key hasn't been revoked
- Ensure no extra spaces/newlines
- For Gemini CLI: Re-run `gemini` to re-authenticate

#### Rate Limits (429)
- O3: Check tier limits, implement backoff
- Gemini: Wait 60s (per-minute limit)
- Consider request batching

#### Missing in CI/CD
```
Warning: O3 API not configured, skipping design request
```
- Verify GitHub secrets are set
- Check secret names match exactly
- Ensure workflow has secret access

### Service-Specific Issues

#### O3 Timeout
- Reduce prompt complexity
- Split into smaller requests
- Increase timeout in scripts

#### Gemini CLI Not Found
- Ensure npm global bin is in PATH
- Check Node.js version (needs 20+)
- Reinstall: `npm install -g @google/gemini-cli`

#### Fallback Not Working
- Check both CLI and API configurations
- Verify error handling in wrappers
- Enable debug logging

## Integration Points

AI services are automatically invoked for:

1. **O3 (Design Decisions)**:
   - Complex build failures
   - Architecture questions
   - Performance optimization
   - Manual trigger: `/ci-force-review o3`

2. **Gemini (Code Reviews)**:
   - Phase completion reviews
   - PR code analysis
   - Implementation feedback
   - Manual trigger: `/ci-force-review gemini`

## Maintenance Schedule

### Daily
- Monitor usage via dashboards
- Check for failed requests
- Review cost alerts

### Weekly
- Generate usage reports
- Analyze request patterns
- Update known-issues with AI solutions

### Monthly
- Rotate API keys
- Review and adjust limits
- Optimize prompt templates
- Evaluate ROI metrics

## Next Steps

1. Complete local setup for both services
2. Add GitHub secrets for CI/CD
3. Run integration tests
4. Monitor first week closely
5. Adjust thresholds based on value

## Support Resources

- OpenAI: [help.openai.com](https://help.openai.com)
- Gemini: [ai.google.dev](https://ai.google.dev)
- Pipeline logs: `tail -f .claude/hook-logs/*.log`
- Cost reports: `nextrust usage-report`

---

With both O3 and Gemini properly configured, the pipeline can leverage the best of both services: O3's advanced reasoning for complex decisions and Gemini's free tier for regular code reviews.