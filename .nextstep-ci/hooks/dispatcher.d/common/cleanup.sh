#!/bin/bash
# hooks/dispatcher.d/common/cleanup.sh - Cleanup and finalization
#
# Purpose: Run cleanup tasks and emit final metrics

# Source metrics if not already loaded
if [[ -f "hooks/dispatcher.d/common/metrics.sh" ]]; then
    source hooks/dispatcher.d/common/metrics.sh
fi

# Emit hook duration metric
if type -t hook_duration >/dev/null 2>&1; then
    hook_duration
fi

# Clean old session files periodically
if [[ $((RANDOM % 100)) -lt 5 ]]; then  # 5% chance
    echo "[$(date)] Running periodic cleanup"
    find .claude/sessions -type f -mtime +7 -delete 2>/dev/null || true
    find .claude/hook-logs -type f -mtime +30 -delete 2>/dev/null || true
    
    if type -t clean_old_metrics >/dev/null 2>&1; then
        clean_old_metrics
    fi
fi

echo "[$(date)] Hook completed: $HOOK_TYPE"