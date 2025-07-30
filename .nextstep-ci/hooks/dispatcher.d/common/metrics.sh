#!/bin/bash
# hooks/dispatcher.d/common/metrics.sh - Enhanced metrics emission for AI activation
#
# Purpose: Export both StatsD and JSONL for local devs without StatsD dependency

set -euo pipefail

# Initialize metrics directories  
METRICS_DIR="docs/ci-status/metrics"
LEGACY_METRICS_FILE=".claude/metrics.csv"
JSONL_METRICS_FILE="$METRICS_DIR/pipeline-metrics-$(date +%Y-%m).jsonl"

mkdir -p "$METRICS_DIR" "$(dirname "$LEGACY_METRICS_FILE")" 2>/dev/null || true

# Emit a metric with both StatsD and JSONL
emit_metric() {
    local metric_name="$1"
    local metric_value="${2:-1}"
    local metric_type="${3:-c}" # c for count, g for gauge, ms for timing
    local tags="${4:-}"
    
    # Flatten metric names (no dots inside tags for StatsD compatibility)
    local flat_name="${metric_name//./_}"
    
    # GitHub Actions annotation
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "::notice title=Metric::${flat_name}=${metric_value} ${tags}"
    fi
    
    # StatsD emission (if configured)
    if [[ -n "${STATSD_HOST:-}" ]]; then
        local statsd_port="${STATSD_PORT:-8125}"
        echo "${flat_name}:${metric_value}|${metric_type}" | nc -u -w0 "$STATSD_HOST" "$statsd_port" 2>/dev/null || true
    fi
    
    # JSONL logging for local development and dashboards
    jq -n \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg name "$flat_name" \
        --arg value "$metric_value" \
        --arg type "$metric_type" \
        --arg tags "$tags" \
        '{timestamp: $timestamp, name: $name, value: ($value | tonumber), type: $type, tags: $tags}' >> "$JSONL_METRICS_FILE"
    
    # Legacy CSV for backward compatibility
    echo "$(date -u +%s),${flat_name},${metric_value},${tags}" >> "$LEGACY_METRICS_FILE"
    
    # Debug output
    if [[ "${NEXTRUST_DEBUG:-0}" == "1" ]]; then
        echo "[METRIC] ${flat_name}=${metric_value}|${metric_type} ${tags}"
    fi
}

# Emit counter metric with AI service-friendly naming
emit_counter() {
    local metric=$1
    local increment=${2:-1}
    local tags=${3:-}
    
    emit_metric "${metric}_total" "$increment" "c" "$tags"
}

# Emit timing metric
emit_timing() {
    local metric=$1
    local duration=$2
    local tags=${3:-}
    
    emit_metric "${metric}_secs" "$duration" "ms" "$tags"
}

# AI service metrics helpers
emit_ai_usage() {
    local service=$1  # "gemini" or "o3"
    local tokens_in=$2
    local tokens_out=$3
    local cost_usd=$4
    local tags=${5:-}
    
    emit_metric "ccusage_tokens_total" "$tokens_in" "c" "service:${service},direction:input,${tags}"
    emit_metric "ccusage_tokens_total" "$tokens_out" "c" "service:${service},direction:output,${tags}"
    emit_metric "ai_cost_usd" "$cost_usd" "g" "service:${service},${tags}"
}

# Automatic hook timing
hook_duration() {
    local duration=$((SECONDS - ${HOOK_START_TIME:-0}))
    local duration_ms=$((duration * 1000))
    
    emit_timing "hook" "$duration_ms" "type:${HOOK_TYPE},tool:${TOOL_NAME}"
    
    # Emit specific metrics based on hook type
    case "$HOOK_TYPE" in
        pre)
            emit_counter "hook.pre_tool_use" 1 "tool:${TOOL_NAME}"
            ;;
        post)
            emit_counter "hook.post_tool_use" 1 "tool:${TOOL_NAME},exit_code:${EXIT_CODE}"
            if [[ "$EXIT_CODE" != "0" ]]; then
                emit_counter "hook.failures" 1 "tool:${TOOL_NAME}"
            fi
            ;;
        stop)
            emit_counter "hook.stop" 1
            ;;
    esac
}

# Clean old metrics (keep last 7 days)
clean_old_metrics() {
    if [[ -f "$METRICS_FILE" ]]; then
        local cutoff=$(date -u +%s -d '7 days ago' 2>/dev/null || date -u +%s)
        local temp_file="${METRICS_FILE}.tmp"
        
        awk -F',' -v cutoff="$cutoff" '$1 >= cutoff' "$METRICS_FILE" > "$temp_file" 2>/dev/null
        mv "$temp_file" "$METRICS_FILE" 2>/dev/null || true
    fi
}