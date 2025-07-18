#!/bin/bash
# hooks/dispatcher.d/common/metrics.sh - Metrics emission helpers
#
# Purpose: Collect and emit metrics for monitoring

# Initialize metrics file
METRICS_FILE=".claude/metrics.csv"
mkdir -p "$(dirname "$METRICS_FILE")" 2>/dev/null || true

# Emit a metric
emit_metric() {
    local metric=$1
    local value=$2
    local tags=${3:-}
    
    # GitHub Actions annotation
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "::notice title=Metric::${metric}=${value} ${tags}"
    fi
    
    # StatsD emission (if configured)
    if [[ -n "${STATSD_HOST:-}" ]]; then
        echo "${metric}:${value}|c|${tags}" | nc -w1 -u "$STATSD_HOST" 8125 2>/dev/null || true
    fi
    
    # Local metrics file (for dashboard queries)
    echo "$(date -u +%s),${metric},${value},${tags}" >> "$METRICS_FILE"
    
    # Debug output
    if [[ "${NEXTRUST_DEBUG:-0}" == "1" ]]; then
        echo "[METRIC] ${metric}=${value} ${tags}"
    fi
}

# Emit counter metric
emit_counter() {
    local metric=$1
    local increment=${2:-1}
    local tags=${3:-}
    
    emit_metric "${metric}.count" "$increment" "$tags"
}

# Emit timing metric
emit_timing() {
    local metric=$1
    local duration=$2
    local tags=${3:-}
    
    emit_metric "${metric}.duration_ms" "$duration" "$tags"
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