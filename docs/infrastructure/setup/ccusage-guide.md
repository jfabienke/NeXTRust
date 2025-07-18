# ccusage Integration Guide

Last updated: 2025-07-18 16:00

## Overview

This guide covers the complete ccusage integration in the NeXTRust CI/CD pipeline, including setup, validation, monitoring, and troubleshooting. The integration provides comprehensive token usage tracking, cost monitoring, and ROI analysis for Claude Code sessions.

## Table of Contents

1. [Architecture](#architecture)
2. [Installation & Setup](#installation--setup)
3. [Usage Examples](#usage-examples)
4. [Validation & Testing](#validation--testing)
5. [Monitoring & Dashboards](#monitoring--dashboards)
6. [Troubleshooting](#troubleshooting)
7. [Best Practices](#best-practices)

## Architecture

### System Components

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│ Data Collection │────▶│ Correlation Layer│────▶│ Analysis Layer  │
│  - Stop Hook    │     │  - Session Match │     │  - Usage Report │
│  - Prompt Audit │     │  - Accuracy Calc │     │  - Cost Monitor │
│  - Metrics      │     │  - Data Update   │     │  - ROI Analysis │
└─────────────────┘     └──────────────────┘     └─────────────────┘
```

### 1. Data Collection Layer

**Stop Hook**: `hooks/dispatcher.d/stop/capture-usage.sh`
- Captures token usage at session end via `ccusage --session-id`
- Calculates costs based on model pricing
- Stores data in JSONL format: `docs/ci-status/metrics/token-usage-YYYYMM.jsonl`
- Emits StatsD metrics for real-time monitoring
- **Resilient Design**: Never fails the pipeline, even if ccusage is unavailable

**Prompt Auditing**: `hooks/dispatcher.d/user-prompt-submit/audit-prompt.sh`
- Captures all prompts with estimated token counts
- Stores session_id for later correlation
- Fields for actual_tokens and estimation_accuracy

### 2. Correlation Layer

**Correlation Script**: `ci/scripts/correlate-token-usage.sh`
- Matches actual usage to prompt estimates
- Calculates estimation accuracy
- Updates prompt audit entries with actual data

### 3. Analysis Layer

**Usage Report Command**: `nextrust usage-report`
- Aggregates usage by phase, user, model, or command type
- Multiple output formats: table, JSON, CSV
- Shows cost breakdown and efficiency metrics
- Calculates average tokens per session

**Cost Monitoring**: `ci/scripts/monitor-costs.sh`
- Runs periodically to check thresholds
- Sends alerts via Slack/email
- Can fail builds on critical overruns
- Tracks spending trends

## Installation & Setup

### Prerequisites

1. Claude Code installed (version 1.0.55+)
2. ccusage available in PATH
3. Python 3.x with typer (for nextrust CLI)

### Quick Setup

```bash
# Verify ccusage is available
which ccusage || echo "ERROR: ccusage not found"

# Test the stop hook
PAYLOAD='{"session_id": "test-123"}' bash hooks/dispatcher.d/stop/capture-usage.sh

# Check if data was captured
tail -1 docs/ci-status/metrics/token-usage-$(date +%Y%m).jsonl | jq .
```

## Usage Examples

### View Current Session Usage

```bash
# Check last session's usage
tail -1 docs/ci-status/metrics/token-usage-$(date +%Y%m).jsonl | jq .

# Pretty-print with costs
tail -1 docs/ci-status/metrics/token-usage-$(date +%Y%m).jsonl | jq '{
  session: .session_id,
  tokens: .tokens.total,
  cost: "$" + (.cost_usd.total | tostring)
}'
```

### Generate Usage Reports

```bash
# Weekly report by phase
nextrust usage-report --days 7 --group-by phase

# Monthly CSV export
nextrust usage-report --days 30 --output-format csv > usage-report.csv

# JSON for dashboards
nextrust usage-report --output-format json | jq .

# Top users report
nextrust usage-report --days 30 --group-by user --limit 10
```

### Monitor Costs

```bash
# Check hourly costs
./ci/scripts/monitor-costs.sh hour

# Check PR costs (requires PR_NUMBER env var)
PR_NUMBER=123 ./ci/scripts/monitor-costs.sh pr

# Daily cost check with alerts
./ci/scripts/monitor-costs.sh day
```

### Correlate Estimates with Actuals

```bash
# Run correlation to update accuracy metrics
./ci/scripts/correlate-token-usage.sh

# Check accuracy trends
jq -s '[.[] | select(.metadata.prompt_metrics.estimation_accuracy != null) | 
       .metadata.prompt_metrics.estimation_accuracy] | 
       {avg: (add/length), min: min, max: max, count: length}' \
    docs/ci-status/metrics/prompt-audit-*.jsonl
```

## Validation & Testing

### Resilience Testing

Create `ci/scripts/test-ccusage-resilience.sh`:

```bash
#!/bin/bash
# Test ccusage failure scenarios

# Test 1: ccusage command not found
echo "Test 1: Missing ccusage command"
PATH=/tmp:$PATH PAYLOAD='{"session_id": "test-fail-1"}' bash hooks/dispatcher.d/stop/capture-usage.sh
echo "Exit code: $?" # Should be 0

# Test 2: ccusage returns error
echo -e "\nTest 2: ccusage returns error"
cat > /tmp/ccusage << 'EOF'
#!/bin/bash
echo "Error: API rate limit exceeded" >&2
exit 1
EOF
chmod +x /tmp/ccusage
PATH="/tmp:$PATH" PAYLOAD='{"session_id": "test-fail-2"}' bash hooks/dispatcher.d/stop/capture-usage.sh
echo "Exit code: $?" # Should be 0

# Test 3: ccusage hangs (timeout test)
echo -e "\nTest 3: ccusage timeout"
cat > /tmp/ccusage << 'EOF'
#!/bin/bash
sleep 30
EOF
chmod +x /tmp/ccusage
PATH="/tmp:$PATH" PAYLOAD='{"session_id": "test-fail-3"}' bash hooks/dispatcher.d/stop/capture-usage.sh
echo "Exit code: $?" # Should be 0

# Verify failure entries were logged
echo -e "\nChecking failure logs:"
grep "capture_failure" docs/ci-status/metrics/token-usage-*.jsonl | tail -3
```

### Alert Testing

```bash
# Temporarily set very low thresholds
jq '.thresholds.cost_per_hour.warning = 0.01 | .thresholds.cost_per_hour.critical = 0.05' \
    ci/config/model-pricing.json > /tmp/low-thresholds.json
cp ci/config/model-pricing.json ci/config/model-pricing.json.bak
mv /tmp/low-thresholds.json ci/config/model-pricing.json

# Trigger alerts
./ci/scripts/monitor-costs.sh hour

# Restore original thresholds
mv ci/config/model-pricing.json.bak ci/config/model-pricing.json
```

### Integration Test Suite

```bash
# Run full test suite
./ci/scripts/test-ccusage-integration.sh

# This validates:
# - Hook installation and execution
# - Cost calculation accuracy
# - Usage report generation
# - Monitoring script functionality
# - Data correlation
```

## Monitoring & Dashboards

### Metrics Collected

- `tokens.input` - Input tokens consumed
- `tokens.output` - Output tokens generated
- `tokens.total` - Total tokens used
- `cost.usd` - Cost in USD
- `ccusage.capture_failed` - Failed capture attempts

### Cost Thresholds

Default thresholds (configurable in `model-pricing.json`):

| Period | Warning | Critical |
|--------|---------|----------|
| Session | $1.00 | $5.00 |
| PR | $5.00 | $20.00 |
| Hour | $10.00 | $50.00 |
| Day | $50.00 | $200.00 |

### Prometheus Exporter

Create `monitoring/ccusage_exporter.py` for Grafana integration:

```python
#!/usr/bin/env python3
import json
import time
from pathlib import Path
from prometheus_client import start_http_server, Counter, Gauge, Histogram

# Metrics
tokens_total = Counter('ccusage_tokens_total', 'Total tokens used', ['model', 'phase', 'user'])
cost_usd = Counter('ccusage_cost_usd_total', 'Total cost in USD', ['model', 'phase', 'user'])
estimation_error = Histogram('ccusage_estimation_error_percent', 'Token estimation error percentage')

def export_metrics():
    metrics_dir = Path("docs/ci-status/metrics")
    
    for usage_file in metrics_dir.glob("token-usage-*.jsonl"):
        with open(usage_file) as f:
            for line in f:
                try:
                    entry = json.loads(line)
                    if entry.get('type') == 'usage_captured':
                        labels = {
                            'model': entry.get('model', 'unknown'),
                            'phase': entry.get('phase', 'unknown'),
                            'user': entry.get('user', 'unknown')
                        }
                        tokens_total.labels(**labels).inc(entry['tokens']['total'])
                        cost_usd.labels(**labels).inc(entry['cost_usd']['total'])
                except:
                    pass

if __name__ == '__main__':
    start_http_server(9091)
    while True:
        export_metrics()
        time.sleep(60)
```

## Troubleshooting

### Common Issues

#### No usage data appearing
1. Check if ccusage is in PATH: `which ccusage`
2. Verify Stop hook is running: `grep "capture-usage" ~/.claude/logs/*`
3. Check for errors: `grep "capture_failure" docs/ci-status/metrics/*`
4. Ensure CCODE_SESSION_ID is set

#### Costs seem incorrect
1. Verify pricing config: `jq . ci/config/model-pricing.json`
2. Check model detection: `grep model docs/ci-status/metrics/token-usage-*.jsonl`
3. Validate calculations manually with known token counts

#### Alerts not firing
1. Test with low threshold: `./ci/scripts/monitor-costs.sh hour`
2. Check Slack webhook: `curl -X POST $SLACK_WEBHOOK_URL -d '{"text":"test"}'`
3. Verify alert conditions in monitoring logs

#### Missing session IDs
1. Ensure CCODE_SESSION_ID is set in environment
2. Check Claude Code version (needs 1.0.55+)
3. Verify session ID is being passed to hooks

#### Correlation failures
1. Run correlation script manually with debug output
2. Check for matching session IDs in both logs
3. Verify both logs exist for the time period

## Best Practices

### Daily Operations
1. Run `nextrust usage-report --days 1` each morning
2. Check for any cost alerts in Slack/email
3. Verify estimation accuracy is >95%

### Weekly Reviews
1. Generate weekly report: `nextrust usage-report --days 7 --output-format csv`
2. Review top consumers and expensive phases
3. Calculate ROI: cost vs time saved
4. Identify optimization opportunities

### Monthly Optimization
1. Analyze usage patterns for trends
2. Review and adjust budget thresholds
3. Update model pricing if needed
4. Share cost reports with stakeholders

### ROI Calculation

Example ROI formula:
```
ROI = (Time_Saved_Hours * Dev_Hourly_Rate + Token_Savings_Value) / Total_Token_Cost
```

Typical values:
- Developer hourly rate: $120/hour
- Average time saved per session: 30 minutes
- Token savings from summarization: ~98%

## Data Schema Reference

### Token Usage Entry
```json
{
  "timestamp": "2025-07-18T10:00:00Z",
  "session_id": "abc-123",
  "model": "claude-3-5-sonnet",
  "phase": "build",
  "user": "developer",
  "tokens": {
    "input": 5000,
    "output": 2000,
    "total": 7000
  },
  "cost_usd": {
    "input": 0.015,
    "output": 0.030,
    "total": 0.045
  },
  "type": "usage_captured"
}
```

### Prompt Audit Entry
```json
{
  "timestamp": "2025-07-18T09:59:00Z",
  "prompt": "Build the LLVM toolchain",
  "session_id": "abc-123",
  "metadata": {
    "prompt_metrics": {
      "estimated_tokens": 6500,
      "actual_tokens": 7000,
      "estimation_accuracy": -7.14
    }
  }
}
```

## Success Metrics

After 30 days of operation, you should see:
- ✅ <5% token estimation error
- ✅ 100% session capture rate (excluding failures)
- ✅ Positive ROI (time saved value > token costs)
- ✅ Proactive cost optimization from usage patterns
- ✅ Reduced debugging time through AI assistance

## Future Enhancements

1. **ML Cost Prediction** - Predict costs before execution
2. **Team Budgets** - Per-team spending limits and reports
3. **Model Optimization** - Auto-switch to cheaper models for simple tasks
4. **Usage Patterns** - Identify and suggest optimization opportunities
5. **Integration with JIRA** - Link costs to specific tickets/features

---

The ccusage integration provides comprehensive visibility into Claude Code token usage, enabling data-driven decisions about AI tool adoption and optimization. With automatic cost tracking, alerts, and ROI analysis, teams can confidently scale their AI-assisted development while maintaining budget control.