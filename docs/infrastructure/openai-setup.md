# OpenAI O3 Service Configuration Guide

*Last updated: 2025-07-20 20:32 EEST*

## 1. Prerequisites

- An active OpenAI account with API access
- Organization Owner or Admin privileges for the `NeXTRust` GitHub repository
- Understanding of API key security best practices

## 2. Required Secrets

The pipeline requires these GitHub repository secrets:

| Secret Name | Purpose | Example Value |
|-------------|---------|---------------|
| `O3_ENDPOINT` | OpenAI API endpoint | `https://api.openai.com/v1/chat/completions` |
| `OPENAI_API_KEY` | OpenAI API key | `sk-proj-...` |
| `GEMINI_API_KEY` | Google AI Studio key | `AI...` |
| `GH_PR_TOKEN` | GitHub PAT for PR comments | `ghp_...` |

## 3. Copy-Pasteable Setup Commands

### 3.1 GitHub Secrets Configuration

```bash
# Navigate to repository settings
# https://github.com/NeXTRust/NeXTRust/settings/secrets/actions

# Add each secret via GitHub UI or CLI:
gh secret set O3_ENDPOINT --body "https://api.openai.com/v1/chat/completions"
gh secret set OPENAI_API_KEY --body "your-openai-key-here"
gh secret set GEMINI_API_KEY --body "your-gemini-key-here" 
gh secret set GH_PR_TOKEN --body "your-github-pat-here"
```

### 3.2 Environment Variables (Local Development)

```bash
# Add to ~/.zshrc or ~/.bashrc
export O3_ENDPOINT="https://api.openai.com/v1/chat/completions"
export OPENAI_API_KEY="sk-proj-your-key-here"
export GEMINI_API_KEY="your-gemini-key-here"
export STATSD_HOST="statsd.example.org:8125"
```

### 3.3 Smoke Test Commands

```bash
# Test OpenAI O3 API
curl -H "Authorization: Bearer $OPENAI_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"model":"o3","messages":[{"role":"user","content":"Hello"}],"max_tokens":50}' \
     "$O3_ENDPOINT"

# Test Gemini CLI
echo "Test prompt" | gemini --model gemini-2.5-pro

# Test GitHub API with PAT
gh api user --token "$GH_PR_TOKEN"
```

## 4. Rate Targets & Limits

- **O3 Design Calls**: ≤10 per day to manage costs
- **Gemini Reviews**: Unlimited (free tier, 1000/day limit)
- **GitHub API**: 5000 requests/hour per token

## 5. Security Considerations

⚠️ **Critical Security Notes**:
- Never commit API keys to the repository
- Use GitHub secrets mechanism exclusively  
- Rotate keys monthly for production usage
- Monitor usage logs for unauthorized access
- Set billing alerts in OpenAI dashboard

### 5.1 Key Rotation Procedure

```bash
# 1. Generate new keys in respective platforms
# 2. Update GitHub secrets
gh secret set OPENAI_API_KEY --body "new-key-here"

# 3. Test with smoke test commands above
# 4. Revoke old keys in platform dashboards
```

## 6. Troubleshooting

### Common Issues

| Issue | Symptoms | Solution |
|-------|----------|----------|
| API key invalid | 401 Unauthorized | Regenerate key, update secret |
| Rate limit hit | 429 Too Many Requests | Wait for reset, check usage |
| Wrong endpoint | 404 Not Found | Verify O3_ENDPOINT format |
| Budget exceeded | 403 Forbidden | Check OpenAI billing dashboard |

### Diagnostic Commands

```bash
# Check secret configuration
gh secret list

# Verify API connectivity  
./ci/scripts/request-ai-service.sh --service o3 --type design --prompt "test"

# Check current usage
./ci/scripts/nextrust usage-report --days 1 --group-by service
```

---

*For operational procedures and troubleshooting, see the [AI Activation Playbook](../ai-activation-playbook.md).*