#!/usr/bin/env bash
# ci/scripts/monitor-costs.sh
#
# Purpose: Monitor token usage costs and send alerts when thresholds are exceeded
# Usage: ./ci/scripts/monitor-costs.sh [--period hour|day|pr]
#
set -uo pipefail

PERIOD="${1:-hour}"
PRICING_CONFIG="ci/config/model-pricing.json"
METRICS_DIR="docs/ci-status/metrics"

echo "=== Cost Monitoring Check ==="
echo "Date: $(date)"
echo "Period: $PERIOD"
echo

# Load pricing config
if [[ ! -f "$PRICING_CONFIG" ]]; then
    echo "Error: Pricing config not found at $PRICING_CONFIG"
    exit 1
fi

# Get thresholds
case "$PERIOD" in
    hour)
        WARNING_THRESHOLD=$(jq -r '.thresholds.cost_per_hour.warning' "$PRICING_CONFIG")
        CRITICAL_THRESHOLD=$(jq -r '.thresholds.cost_per_hour.critical' "$PRICING_CONFIG")
        TIME_WINDOW=3600  # seconds
        ;;
    day)
        WARNING_THRESHOLD=$(jq -r '.thresholds.cost_per_day.warning' "$PRICING_CONFIG")
        CRITICAL_THRESHOLD=$(jq -r '.thresholds.cost_per_day.critical' "$PRICING_CONFIG")
        TIME_WINDOW=86400  # seconds
        ;;
    pr)
        # For PR, we need to get the current PR number
        PR_NUMBER="${GITHUB_PR_NUMBER:-${PR_NUMBER:-unknown}}"
        WARNING_THRESHOLD=$(jq -r '.thresholds.cost_per_pr.warning' "$PRICING_CONFIG")
        CRITICAL_THRESHOLD=$(jq -r '.thresholds.cost_per_pr.critical' "$PRICING_CONFIG")
        TIME_WINDOW=0  # Not time-based
        ;;
    *)
        echo "Invalid period: $PERIOD (use hour, day, or pr)"
        exit 1
        ;;
esac

# Calculate costs for the period
CURRENT_TIME=$(date +%s)
CUTOFF_TIME=$((CURRENT_TIME - TIME_WINDOW))
TOTAL_COST=0
SESSION_COUNT=0

# Read usage data
for usage_file in "$METRICS_DIR"/token-usage-*.jsonl; do
    if [[ ! -f "$usage_file" ]]; then
        continue
    fi
    
    while IFS= read -r line; do
        # Skip non-usage entries
        if ! echo "$line" | jq -e '.type == "usage_captured"' >/dev/null 2>&1; then
            continue
        fi
        
        # Check if entry is in our time window (or matches PR)
        if [[ "$PERIOD" == "pr" ]]; then
            # For PR monitoring, we'd need to correlate with PR metadata
            # For now, just accumulate all costs
            ENTRY_COST=$(echo "$line" | jq -r '.cost_usd.total // 0' 2>/dev/null || echo "0")
        else
            # Time-based check
            ENTRY_TIME=$(echo "$line" | jq -r '.timestamp' 2>/dev/null | xargs -I {} date -d {} +%s 2>/dev/null || echo "0")
            if [[ $ENTRY_TIME -lt $CUTOFF_TIME ]]; then
                continue
            fi
            ENTRY_COST=$(echo "$line" | jq -r '.cost_usd.total // 0' 2>/dev/null || echo "0")
        fi
        
        TOTAL_COST=$(awk "BEGIN {printf \"%.6f\", $TOTAL_COST + $ENTRY_COST}")
        ((SESSION_COUNT++))
    done < "$usage_file"
done

echo "Period Cost: \$$TOTAL_COST"
echo "Sessions: $SESSION_COUNT"
echo "Warning Threshold: \$$WARNING_THRESHOLD"
echo "Critical Threshold: \$$CRITICAL_THRESHOLD"
echo

# Check thresholds
ALERT_LEVEL="none"
ALERT_MESSAGE=""

if (( $(awk "BEGIN {print ($TOTAL_COST > $CRITICAL_THRESHOLD)}") )); then
    ALERT_LEVEL="critical"
    ALERT_MESSAGE="🚨 CRITICAL: $PERIOD cost (\$$TOTAL_COST) exceeds critical threshold (\$$CRITICAL_THRESHOLD)"
elif (( $(awk "BEGIN {print ($TOTAL_COST > $WARNING_THRESHOLD)}") )); then
    ALERT_LEVEL="warning"
    ALERT_MESSAGE="⚠️  WARNING: $PERIOD cost (\$$TOTAL_COST) exceeds warning threshold (\$$WARNING_THRESHOLD)"
else
    echo "✅ Costs within acceptable range"
fi

# Send alerts if needed
if [[ "$ALERT_LEVEL" != "none" ]]; then
    echo "$ALERT_MESSAGE"
    
    # Log alert
    ALERT_ENTRY=$(jq -n \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg level "$ALERT_LEVEL" \
        --arg period "$PERIOD" \
        --arg message "$ALERT_MESSAGE" \
        --argjson cost "$TOTAL_COST" \
        --argjson threshold "$WARNING_THRESHOLD" \
        --argjson sessions "$SESSION_COUNT" \
        '{
            timestamp: $timestamp,
            alert_level: $level,
            period: $period,
            message: $message,
            cost_usd: $cost,
            threshold_usd: $threshold,
            session_count: $sessions,
            type: "cost_alert"
        }')
    
    echo "$ALERT_ENTRY" >> "$METRICS_DIR/cost-alerts-$(date +%Y%m).jsonl"
    
    # Send Slack notification if configured
    SLACK_WEBHOOK=$(jq -r '.budget_alerts.slack_webhook // empty' "$PRICING_CONFIG" 2>/dev/null)
    ALERTS_ENABLED=$(jq -r '.budget_alerts.enabled // false' "$PRICING_CONFIG" 2>/dev/null)
    
    if [[ "$ALERTS_ENABLED" == "true" ]] && [[ -n "$SLACK_WEBHOOK" ]] && [[ "$SLACK_WEBHOOK" != "null" ]]; then
        # Evaluate environment variable if present
        SLACK_WEBHOOK=$(eval echo "$SLACK_WEBHOOK")
        
        if [[ -n "$SLACK_WEBHOOK" ]] && [[ "$SLACK_WEBHOOK" =~ ^https:// ]]; then
            SLACK_PAYLOAD=$(jq -n \
                --arg text "$ALERT_MESSAGE" \
                --arg period "$PERIOD" \
                --argjson cost "$TOTAL_COST" \
                --argjson sessions "$SESSION_COUNT" \
                '{
                    text: $text,
                    attachments: [{
                        color: ($level == "critical" ? "danger" : "warning"),
                        fields: [
                            {title: "Period", value: $period, short: true},
                            {title: "Total Cost", value: ("$" + ($cost | tostring)), short: true},
                            {title: "Sessions", value: ($sessions | tostring), short: true},
                            {title: "Avg Cost/Session", value: ("$" + (($cost / $sessions) | tostring)), short: true}
                        ]
                    }]
                }')
            
            curl -X POST -H 'Content-type: application/json' \
                --data "$SLACK_PAYLOAD" \
                "$SLACK_WEBHOOK" 2>/dev/null || echo "Failed to send Slack alert"
        fi
    fi
    
    # Update pipeline status
    if command -v python3 &>/dev/null && [[ -x "ci/scripts/status-append.py" || -x "$(which status-append.py 2>/dev/null)" ]]; then
        python3 ci/scripts/status-append.py "$ALERT_LEVEL" "$ALERT_MESSAGE" 2>/dev/null || true
    fi
    
    # For critical alerts, consider failing the build
    if [[ "$ALERT_LEVEL" == "critical" ]] && [[ "${FAIL_ON_COST_OVERRUN:-false}" == "true" ]]; then
        echo "ERROR: Critical cost threshold exceeded. Failing build."
        exit 1
    fi
fi

echo
echo "=== Cost Monitoring Complete ==="