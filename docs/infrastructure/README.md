# NeXTRust CI Infrastructure Documentation

Last updated: 2025-07-18 16:45

## Quick Navigation

### Core Documentation
- **[CI Architecture Overview](ci-architecture-overview.md)** - High-level system design and components
- **[CI Pipeline Guide](ci-pipeline.md)** - Detailed pipeline documentation (v2.0)
- **[Slash Commands Reference](ci-slash-commands.md)** - PR comment commands for CI control

### Setup Guides
- **[AI Services Setup](setup/ai-services-setup.md)** - Configure OpenAI O3 and Gemini integrations
- **[ccusage Integration](setup/ccusage-guide.md)** - Token usage tracking and cost monitoring

### Advanced Topics
- **[Claude Code Integration](guides/claude-code-integration.md)** - Deep integration features and patterns
- **[Troubleshooting Guide](guides/troubleshooting.md)** - Comprehensive troubleshooting reference

## Overview

The NeXTRust CI/CD infrastructure is built on a Claude Code-first architecture that leverages AI assistance at every stage of the development pipeline. Version 2.0 introduces a modular dispatcher system with enhanced robustness and comprehensive monitoring.

## Key Features

### 🤖 AI-Driven Pipeline
- **Claude Code** as primary orchestrator (90% of decisions)
- **OpenAI O3** for complex design decisions
- **Gemini 2.5 Pro** for code reviews (FREE tier)

### 🔧 Modular Architecture
- Thin dispatcher router (~30 lines)
- Organized module system in `hooks/dispatcher.d/`
- Clear separation of concerns
- Easy to extend and maintain

### 💰 Cost Management
- Automatic token usage tracking via ccusage
- Real-time cost monitoring and alerts
- ROI analysis and reporting
- Budget controls per session/PR/day

### 🛡️ Security & Reliability
- Input validation for all slash commands
- Persistent failure tracking
- Composite idempotency keys
- File locking with timeout handling
- Per-commit backoff protection

### 📊 Observability
- StatsD metrics integration
- Grafana-ready dashboards
- Comprehensive audit logging
- Usage analytics and trends

## Quick Start

### For Developers

1. **Set up AI services**:
   ```bash
   # Add to ~/.zshrc
   export OPENAI_API_KEY="sk-..."
   export O3_ENDPOINT="https://api.openai.com/v1"
   
   # Install Gemini CLI
   npm install -g @google/gemini-cli
   ```

2. **Test the pipeline**:
   ```bash
   ./ci/scripts/test-all-simple.sh
   ```

3. **Monitor usage**:
   ```bash
   nextrust usage-report --days 7
   ```

### For CI/CD Engineers

1. **Deploy v2 architecture**:
   ```bash
   ./ci/scripts/migrate-to-v2.sh
   ```

2. **Configure GitHub secrets**:
   - `OPENAI_API_KEY`
   - `O3_ENDPOINT`
   - `GEMINI_API_KEY` (optional)

3. **Set up monitoring**:
   - Deploy Prometheus exporter
   - Import Grafana dashboards
   - Configure alerts

## Slash Commands

Control the CI pipeline directly from PR comments:

| Command | Description |
|---------|-------------|
| `/ci-help` | Show available commands |
| `/ci-status` | Current pipeline status |
| `/ci-retry-job <name>` | Retry a failed job |
| `/ci-force-review gemini` | Trigger code review |
| `/ci-force-review o3` | Request design guidance |

[Full command reference →](ci-slash-commands.md)

## Cost Optimization

### Current Pricing (as of 2025-07-18)
- **Claude 3.5 Sonnet**: $3/M input, $15/M output
- **OpenAI O3**: $2/M input, $8/M output (10x reduction!)
- **Gemini 2.5 Pro**: FREE via CLI (1000/day limit)

### Best Practices
1. Use Gemini CLI for regular reviews (free)
2. Reserve O3 for complex design decisions
3. Monitor daily costs with `nextrust usage-report`
4. Set budget alerts in `model-pricing.json`

## Architecture Diagram

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   GitHub PR     │────▶│  Claude Code     │────▶│   AI Services   │
│   /commands     │     │  (Orchestrator)  │     │  - O3 (design)  │
└─────────────────┘     └──────────────────┘     │  - Gemini (review)│
                               │                  └─────────────────┘
                               ▼
                    ┌──────────────────┐
                    │ Hook Dispatcher  │
                    │  - Pre-checks    │
                    │  - Post-analysis │
                    │  - Metrics       │
                    └──────────────────┘
```

## Maintenance

### Daily Tasks
- Check cost alerts
- Review failure logs
- Monitor rate limits

### Weekly Tasks
- Generate usage reports
- Analyze error patterns
- Update known-issues database

### Monthly Tasks
- Rotate API keys
- Review budget thresholds
- Optimize prompt templates

## Troubleshooting

Common issues and solutions:

1. **No token usage data**:
   - Verify ccusage is installed
   - Check Stop hook is running
   - Look for errors in metrics logs

2. **AI service failures**:
   - Check API keys are set
   - Verify rate limits
   - Review error handling logs

3. **Slash commands not working**:
   - Ensure user has write permissions
   - Check command syntax
   - Review audit logs

## Contributing

When updating the CI infrastructure:

1. Test changes locally first
2. Update relevant documentation
3. Run integration tests
4. Monitor rollout closely

## Support

- Pipeline logs: `.claude/hook-logs/`
- Metrics: `docs/ci-status/metrics/`
- Issues: Create GitHub issue with `ci-infrastructure` label

---

*The NeXTRust CI pipeline demonstrates how AI-assisted development can be both powerful and cost-effective when properly architected.*