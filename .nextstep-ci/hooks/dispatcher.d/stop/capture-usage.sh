#!/bin/bash
# hooks/dispatcher.d/stop/capture-usage.sh
#
# Purpose: Capture Claude Code token usage at session end
# CRITICAL: Must be resilient - never fail the pipeline
#
# This hook is called when a Claude Code session ends, allowing us to
# capture actual token usage for cost tracking and optimization.
#
set +e  # Do NOT exit on error - this is metrics collection

echo "[$(date)] Starting usage capture for session"

# Extract session ID from payload or environment
SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id // empty' 2>/dev/null)
if [[ -z "$SESSION_ID" ]]; then
    SESSION_ID="${CCODE_SESSION_ID:-unknown}"
fi

# Source availability checker if available
if [[ -f "ci/scripts/check-ccusage.sh" ]]; then
    source ci/scripts/check-ccusage.sh
    if ! ensure_ccusage_or_skip; then
        exit 0
    fi
else
    # Fallback to simple check
    if ! command -v ccusage &>/dev/null; then
        echo "[$(date)] ccusage not available, skipping usage capture" >&2
        exit 0
    fi
fi

# Ensure metrics directory exists
METRICS_DIR="docs/ci-status/metrics"
mkdir -p "$METRICS_DIR"

# Capture usage with timeout and error handling
echo "[$(date)] Calling ccusage for session: $SESSION_ID"
USAGE_JSON=$(timeout 10s ccusage --session-id "$SESSION_ID" --format json 2>/dev/null)
CCUSAGE_EXIT=$?

if [[ $CCUSAGE_EXIT -ne 0 ]]; then
    # Log error but don't fail
    echo "[$(date)] ccusage failed with exit code $CCUSAGE_EXIT" >&2
    
    # Log failure to metrics file for tracking
    FAILURE_ENTRY=$(jq -n \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg session "$SESSION_ID" \
        --arg error "ccusage_failed" \
        --argjson exit_code "$CCUSAGE_EXIT" \
        '{
            timestamp: $timestamp,
            session_id: $session,
            error: $error,
            exit_code: $exit_code,
            type: "capture_failure"
        }')
    
    echo "$FAILURE_ENTRY" | jq -c . >> "$METRICS_DIR/token-usage-$(date +%Y%m).jsonl"
    
    # Emit failure metric if StatsD available
    if command -v nc &>/dev/null && [[ -n "${STATSD_HOST:-}" ]]; then
        echo "ccusage.capture_failed:1|c" | nc -w1 -u "$STATSD_HOST" "${STATSD_PORT:-8125}" 2>/dev/null || true
    fi
    
    exit 0
fi

# Parse the usage data
INPUT_TOKENS=$(echo "$USAGE_JSON" | jq -r '.input_tokens // 0' 2>/dev/null || echo "0")
OUTPUT_TOKENS=$(echo "$USAGE_JSON" | jq -r '.output_tokens // 0' 2>/dev/null || echo "0")
TOTAL_TOKENS=$(echo "$USAGE_JSON" | jq -r '.total_tokens // 0' 2>/dev/null || echo "0")
MODEL=$(echo "$USAGE_JSON" | jq -r '.model // "unknown"' 2>/dev/null || echo "unknown")

# Calculate cost (prices in USD per 1M tokens)
# Default to Claude 3.5 Sonnet pricing if model not specified
case "$MODEL" in
    *opus*)
        INPUT_PRICE=15.00
        OUTPUT_PRICE=75.00
        ;;
    *haiku*)
        INPUT_PRICE=0.25
        OUTPUT_PRICE=1.25
        ;;
    *)  # Default to Sonnet
        INPUT_PRICE=3.00
        OUTPUT_PRICE=15.00
        ;;
esac

# Calculate costs in USD
INPUT_COST=$(awk "BEGIN {printf \"%.6f\", $INPUT_TOKENS * $INPUT_PRICE / 1000000}")
OUTPUT_COST=$(awk "BEGIN {printf \"%.6f\", $OUTPUT_TOKENS * $OUTPUT_PRICE / 1000000}")
TOTAL_COST=$(awk "BEGIN {printf \"%.6f\", $INPUT_COST + $OUTPUT_COST}")

# Get additional context
PHASE_FILE="docs/ci-status/pipeline-log.json"
if [[ -f "$PHASE_FILE" ]]; then
    PHASE_ID=$(jq -r '.current_phase.id // "unknown"' "$PHASE_FILE" 2>/dev/null || echo "unknown")
else
    PHASE_ID="unknown"
fi

# Create usage entry
USAGE_ENTRY=$(jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg session "$SESSION_ID" \
    --arg model "$MODEL" \
    --arg phase "$PHASE_ID" \
    --arg user "${USER:-unknown}" \
    --argjson input_tokens "$INPUT_TOKENS" \
    --argjson output_tokens "$OUTPUT_TOKENS" \
    --argjson total_tokens "$TOTAL_TOKENS" \
    --argjson input_cost "$INPUT_COST" \
    --argjson output_cost "$OUTPUT_COST" \
    --argjson total_cost "$TOTAL_COST" \
    '{
        timestamp: $timestamp,
        session_id: $session,
        model: $model,
        phase: $phase,
        user: $user,
        tokens: {
            input: $input_tokens,
            output: $output_tokens,
            total: $total_tokens
        },
        cost_usd: {
            input: $input_cost,
            output: $output_cost,
            total: $total_cost
        },
        type: "usage_captured"
    }')

# Append to metrics file (compact JSON for JSONL format)
echo "$USAGE_ENTRY" | jq -c . >> "$METRICS_DIR/token-usage-$(date +%Y%m).jsonl"

echo "[$(date)] Usage captured: $TOTAL_TOKENS tokens, cost: \$$TOTAL_COST"

# Emit StatsD metrics if available
if command -v nc &>/dev/null && [[ -n "${STATSD_HOST:-}" ]]; then
    {
        echo "tokens.input:$INPUT_TOKENS|c|#model:$MODEL,phase:$PHASE_ID"
        echo "tokens.output:$OUTPUT_TOKENS|c|#model:$MODEL,phase:$PHASE_ID"
        echo "tokens.total:$TOTAL_TOKENS|c|#model:$MODEL,phase:$PHASE_ID"
        echo "cost.usd:$TOTAL_COST|g|#model:$MODEL,phase:$PHASE_ID"
    } | nc -w1 -u "$STATSD_HOST" "${STATSD_PORT:-8125}" 2>/dev/null || true
fi

# Update session correlation in prompt log if we have a session ID
if [[ "$SESSION_ID" != "unknown" ]] && [[ -f "$METRICS_DIR/prompt-audit-$(date +%Y%m).jsonl" ]]; then
    # This would update the prompt audit entries with actual tokens
    # For now, just log that we would do this
    echo "[$(date)] Would update prompt audit entries for session $SESSION_ID with actual tokens"
fi

# Check for cost alerts
if (( $(awk "BEGIN {print ($TOTAL_COST > 1.0)}") )); then
    echo "[$(date)] ⚠️  High cost session: \$$TOTAL_COST for $TOTAL_TOKENS tokens" >&2
    
    # Log high-cost alert
    if command -v python3 &>/dev/null && [[ -x "ci/scripts/status-append.py" || -x "$(which status-append.py 2>/dev/null)" ]]; then
        python3 ci/scripts/status-append.py "cost_alert" \
            "{\"session_id\": \"$SESSION_ID\", \"cost_usd\": $TOTAL_COST, \"tokens\": $TOTAL_TOKENS}" 2>/dev/null || true
    fi
fi

echo "[$(date)] Usage capture completed successfully"
exit 0