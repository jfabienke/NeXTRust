# AI Activation Pre-Flight Checklist

*Last updated: 2025-07-20 21:02 EEST*

## ✅ Local Tests Completed (8/10)

| Test | Status | Verification |
|------|--------|--------------|
| Slash command manual review | ✅ | `ci-ai-review.sh` detected 13 files |
| O3 phase-completion trigger | ✅ | Hook fired, metrics emitted |
| Manual O3 design help | ✅ | Help interface with cost warnings |
| Budget guard enforcement | ✅ | Alert triggered at $0.005 limit |
| Metrics emission | ✅ | JSONL metrics with ISO timestamps |
| Help UX | ✅ | AI commands visible in `/ci-help` |

## 🚀 GitHub-Only Tests Checklist

### Pre-Push Requirements

#### 1. GitHub Secrets Configuration
- [ ] `GEMINI_API_KEY` - Google AI Studio key
- [ ] `OPENAI_API_KEY` - OpenAI API key  
- [ ] `O3_ENDPOINT` - https://api.openai.com/v1/chat/completions
- [ ] `GH_PR_TOKEN` - GitHub PAT with `pull-requests: write`
- [ ] `STATSD_HOST` - Optional metrics endpoint
- [ ] `SLACK_WEBHOOK_URL` - Optional budget alerts

#### 2. Workflow Files Verification
```bash
# Verify all workflows are syntactically valid
for workflow in .github/workflows/*.yml; do
  echo "Checking $workflow..."
  python -m yaml $workflow || echo "FAILED: $workflow"
done
```

#### 3. Branch Protection Updates
- [ ] Add `pr-review` to required status checks
- [ ] Exclude `test/*` branches from protection (optional)
- [ ] Enable "Dismiss stale PR reviews" for AI re-reviews

### Remote Test Execution Plan

#### Test 1: Gemini Auto-Review on PR
```bash
# 1. Create test branch and push
git checkout -b test/ai-review-validation
git commit --allow-empty -m "test: Validate AI review workflow"
git push -u origin test/ai-review-validation

# 2. Open PR via CLI
gh pr create --title "Test: AI Review Validation" \
  --body "Testing automated Gemini reviews" \
  --label "ci/run"

# 3. Monitor workflow
gh run watch
```

**Success Indicators:**
- Workflow `pr-review` starts within 30s
- Gemini comment appears within 90s
- Metrics show `gemini_review_secs` entry

#### Test 2: Slash Command in PR
```bash
# In the PR comments
gh pr comment --body "/ci-ai-review --service gemini"

# Monitor response
gh pr view --comments
```

**Success Indicators:**
- Bot responds with "🔄 Review queued"
- Gemini review posted within 2 minutes
- Metrics show `slash_command` with `command:ai-review`

#### Test 3: Budget Monitor Artifact
```bash
# Trigger maintenance workflow
gh workflow run maintenance.yml

# Check artifacts
gh run list --workflow=maintenance.yml --limit 1
gh run download <run-id> -n ai-metrics-*
```

**Success Indicators:**
- `ai-metrics-YYYY-MM-DD.csv` artifact created
- CSV contains cost breakdowns
- Summary shows budget status

#### Test 4: Stop Hook Capture
```bash
# Method 1: Label trigger
gh pr edit --add-label "ci/hold"

# Method 2: Environment variable
git commit --allow-empty -m "test: Trigger stop hook

HOOK_STOP=1"
git push
```

**Success Indicators:**
- Metrics show `stop_hook` entry
- Job status shows as "neutral" (yellow)
- Usage capture in `docs/ci-status/usage/`

### Post-Deployment Verification

#### Grafana Dashboard (Docker)
```bash
# Start Grafana stack
cd ops/grafana
docker-compose up -d

# Access dashboard
open http://localhost:3000
# Default: admin/admin

# Import dashboard
# Settings → Data Sources → Add Prometheus
# Dashboards → Import → Upload JSON
```

#### API Endpoint Tests
```bash
# Test Gemini CLI
echo "Test prompt" | gemini --model gemini-2.5-pro

# Test O3 endpoint
curl -H "Authorization: Bearer $OPENAI_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"model":"gpt-4","messages":[{"role":"user","content":"ping"}]}' \
     "$O3_ENDPOINT"

# Test GitHub API access
gh api user --header "Authorization: token $GH_PR_TOKEN"
```

### Rollback Plan

If issues arise:
```bash
# Disable PR workflow
gh workflow disable pr-review

# Revert to previous pricing limits
git checkout main -- ci/config/model-pricing.json

# Clear budget state
rm -f .claude/budget-state.json
```

### Monitoring Commands

```bash
# Check recent AI usage
./ci/scripts/budget-monitor.py status --days 1

# View metrics dashboard
python3 ci/scripts/metrics-dashboard.py --format text

# Check hook logs
tail -f .claude/hook-logs/$(date +%Y-%m-%d).log

# Monitor workflow runs
gh run list --workflow=pr-review --limit 5
```

## 🎯 Production Readiness

- [ ] All 10 verification tests passing
- [ ] Secrets configured and validated
- [ ] Budget limits appropriate for team size
- [ ] Monitoring dashboards operational
- [ ] Team notified of new slash commands

---

*Once all checks pass, the AI activation system is ready for production use!*