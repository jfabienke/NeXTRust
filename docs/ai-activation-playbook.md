# NeXTRust AI Activation Playbook

*Last updated: 2025-07-20 20:30 EEST*

## 1. Why We're Adding AI

The NeXTRust project leverages AI services to accelerate development velocity while maintaining code quality. By automating code reviews and providing architectural guidance at critical junctures, we reduce iteration time and improve decision-making consistency across the complex cross-compilation challenges of targeting historic NeXTSTEP systems.

## 2. Service Matrix

| Service | Purpose | Trigger | Output | Cost Model |
|---------|---------|---------|--------|------------|
| **Gemini 2.5 Pro** | Code reviews | Every PR | GitHub comment | FREE (CLI, 1000/day limit) |
| **OpenAI O3** | Design decisions | Phase boundaries | Pipeline log entry | $2/M input, $8/M output |

### Usage Patterns
- **Gemini**: Triggered automatically on PRs via `pr-review.yml`, analyzes changed files against `GEMINI.md` guidelines
- **O3**: Triggered by `90-phase-complete.sh` stop hook when phases transition, provides architectural input for next phase

## 3. Operational Guard-Rails

### Budget Controls
- **Monthly cap**: $500 total ($30 Gemini buffer, $300 O3 design calls)
- **Alert threshold**: 80% of monthly budget
- **Rate limiting**: ≤10 O3 design calls per day
- **Daily monitoring**: `budget-monitor.py` runs via `maintenance.yml`

### Cost Tracking
- All usage logged to `docs/ci-status/usage/*.jsonl` 
- Token counts captured via `ccusage` integration
- Cost attribution by service, phase, and user
- Metrics exported to StatsD: `ccusage_tokens_total`, `gemini_review_secs`

### Failsafe Mechanisms
- O3 response caching (SHA-256 keyed) prevents duplicate API calls
- GitHub secrets isolation prevents credential exposure
- Budget violations trigger Slack alerts and service suspension

## 4. Runbook Links

### Daily Operations
- **Check AI costs**: `./ci/scripts/nextrust usage-report --days 1 --group-by service`
- **Manual review**: `/ci-ai-review` (slash command in PR)
- **Design help**: `/ci-design-help "atomic spinlocks hanging"` (slash command)
- **Metrics dashboard**: `python3 ci/scripts/metrics-dashboard.py --days 7`

### Troubleshooting
- **Budget overrun**: Check `budget-monitor.py` output and Slack alerts
- **Gemini failures**: Verify `GEMINI_API_KEY` secret and CLI installation
- **O3 timeouts**: Check API endpoint and key validity
- **Missing reviews**: Verify PR permissions and workflow triggers

### Monitoring Endpoints
- **Pipeline status**: `docs/ci-status/pipeline-log.md`
- **Usage logs**: `docs/ci-status/usage/`
- **Metrics export**: StatsD at `${STATSD_HOST}:8125`
- **Budget status**: Daily cron in `maintenance.yml`

---

*This playbook is version-controlled and updated as the AI infrastructure evolves. For implementation details, see `docs/infrastructure/openai-setup.md` and the engineering notes in each phase's PR description.*