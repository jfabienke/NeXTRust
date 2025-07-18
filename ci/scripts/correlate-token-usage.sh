#!/usr/bin/env bash
# ci/scripts/correlate-token-usage.sh
#
# Purpose: Correlate actual token usage from ccusage with prompt estimates
# This script is called periodically to update prompt audit entries with actual usage
#
set -uo pipefail

echo "=== Correlating Token Usage ==="
echo "Date: $(date)"

METRICS_DIR="docs/ci-status/metrics"
CURRENT_MONTH=$(date +%Y%m)

# Check if we have both files
PROMPT_FILE="$METRICS_DIR/prompt-audit-$CURRENT_MONTH.jsonl"
USAGE_FILE="$METRICS_DIR/token-usage-$CURRENT_MONTH.jsonl"

if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "No prompt audit file found for current month"
    exit 0
fi

if [[ ! -f "$USAGE_FILE" ]]; then
    echo "No token usage file found for current month"
    exit 0
fi

# Create a temporary file for updated entries
TEMP_FILE=$(mktemp)
CORRELATIONS_MADE=0
TOTAL_PROMPTS=0

# Process each prompt entry
while IFS= read -r line; do
    ((TOTAL_PROMPTS++))
    
    # Extract session ID from prompt entry
    SESSION_ID=$(echo "$line" | jq -r '.session_id // empty' 2>/dev/null)
    
    if [[ -z "$SESSION_ID" ]] || [[ "$SESSION_ID" == "unknown" ]]; then
        # No session ID, can't correlate
        echo "$line" >> "$TEMP_FILE"
        continue
    fi
    
    # Check if we already have actual tokens
    ACTUAL_TOKENS=$(echo "$line" | jq -r '.metadata.prompt_metrics.actual_tokens // empty' 2>/dev/null)
    if [[ -n "$ACTUAL_TOKENS" ]] && [[ "$ACTUAL_TOKENS" != "null" ]]; then
        # Already correlated
        echo "$line" >> "$TEMP_FILE"
        continue
    fi
    
    # Look for matching usage entry
    USAGE_ENTRY=$(grep "\"session_id\":\"$SESSION_ID\"" "$USAGE_FILE" | grep '"type":"usage_captured"' | tail -1)
    
    if [[ -n "$USAGE_ENTRY" ]]; then
        # Extract actual token count
        ACTUAL_TOKENS=$(echo "$USAGE_ENTRY" | jq -r '.tokens.total // 0' 2>/dev/null || echo "0")
        ESTIMATED_TOKENS=$(echo "$line" | jq -r '.metadata.prompt_metrics.estimated_tokens // 0' 2>/dev/null || echo "0")
        
        # Calculate estimation accuracy
        if [[ "$ACTUAL_TOKENS" -gt 0 ]]; then
            ACCURACY=$(awk "BEGIN {printf \"%.2f\", (($ESTIMATED_TOKENS - $ACTUAL_TOKENS) / $ACTUAL_TOKENS) * 100}")
        else
            ACCURACY=0
        fi
        
        # Update the entry with actual tokens and accuracy
        UPDATED_LINE=$(echo "$line" | jq \
            --argjson actual "$ACTUAL_TOKENS" \
            --argjson accuracy "$ACCURACY" \
            '.metadata.prompt_metrics.actual_tokens = $actual | 
             .metadata.prompt_metrics.estimation_accuracy = $accuracy')
        
        echo "$UPDATED_LINE" >> "$TEMP_FILE"
        ((CORRELATIONS_MADE++))
        
        echo "Correlated session $SESSION_ID: estimated=$ESTIMATED_TOKENS, actual=$ACTUAL_TOKENS, accuracy=${ACCURACY}%"
    else
        # No usage data found yet
        echo "$line" >> "$TEMP_FILE"
    fi
done < "$PROMPT_FILE"

# Replace the original file if we made any correlations
if [[ $CORRELATIONS_MADE -gt 0 ]]; then
    mv "$TEMP_FILE" "$PROMPT_FILE"
    echo
    echo "✅ Updated $CORRELATIONS_MADE entries out of $TOTAL_PROMPTS total"
    
    # Calculate average estimation accuracy
    AVG_ACCURACY=$(jq -s '
        [.[] | select(.metadata.prompt_metrics.estimation_accuracy != null) | 
         .metadata.prompt_metrics.estimation_accuracy] | 
        if length > 0 then add/length else 0 end
    ' "$PROMPT_FILE" 2>/dev/null || echo "0")
    
    echo "Average estimation accuracy: ${AVG_ACCURACY}%"
    
    # Log correlation summary
    if command -v python3 &>/dev/null && [[ -x "ci/scripts/status-append.py" || -x "$(which status-append.py 2>/dev/null)" ]]; then
        python3 ci/scripts/status-append.py "token_correlation" \
            "{\"correlations_made\": $CORRELATIONS_MADE, \"avg_accuracy\": $AVG_ACCURACY}" 2>/dev/null || true
    fi
else
    rm -f "$TEMP_FILE"
    echo "No new correlations made"
fi

echo
echo "=== Correlation Complete ==="