#!/bin/bash
# hooks/dispatcher.d/tool-output/summarize-build-logs.sh
#
# Purpose: Intercept and summarize large build outputs before sending to Claude
# Reduces token usage while preserving important information
#
set -uo pipefail

# Note: ToolOutput hooks must output the (potentially modified) payload
# to stdout for Claude Code to use

# Parse the payload
TOOL_NAME=$(echo "$PAYLOAD" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
COMMAND=$(echo "$PAYLOAD" | jq -r '.tool_args.command // ""' 2>/dev/null || echo "")
STDOUT_RAW=$(echo "$PAYLOAD" | jq -r '.tool_response.stdout // ""' 2>/dev/null || echo "")
STDERR_RAW=$(echo "$PAYLOAD" | jq -r '.tool_response.stderr // ""' 2>/dev/null || echo "")
EXIT_CODE=$(echo "$PAYLOAD" | jq -r '.tool_response.exit_code // 0' 2>/dev/null || echo "0")

# Calculate output sizes
STDOUT_SIZE=$(echo -n "$STDOUT_RAW" | wc -c)
STDERR_SIZE=$(echo -n "$STDERR_RAW" | wc -c)
TOTAL_SIZE=$((STDOUT_SIZE + STDERR_SIZE))

# Define size threshold (10KB)
SIZE_THRESHOLD=10000

# List of commands that typically produce large outputs
NOISY_COMMANDS=(
    "build-custom-llvm.sh"
    "cargo build"
    "cargo test"
    "cmake"
    "make"
    "npm install"
    "pip install"
)

# Check if this is a noisy command
IS_NOISY=false
for noisy_cmd in "${NOISY_COMMANDS[@]}"; do
    if [[ "$COMMAND" == *"$noisy_cmd"* ]]; then
        IS_NOISY=true
        break
    fi
done

# Process based on output size and command type
if [[ $TOTAL_SIZE -gt $SIZE_THRESHOLD ]] || [[ "$IS_NOISY" == "true" && $TOTAL_SIZE -gt 5000 ]]; then
    # Log to stderr so it doesn't interfere with the JSON output
    echo "[$(date)] Large output detected ($TOTAL_SIZE bytes), summarizing..." >&2
    
    # Create summary header
    SUMMARY_HEADER="[CI-NOTE: Output summarized. Original size: $TOTAL_SIZE bytes]"
    
    # Extract key information from stdout
    if [[ $STDOUT_SIZE -gt 1000 ]]; then
        # Extract errors, warnings, and key status messages
        STDOUT_SUMMARY=$(echo "$STDOUT_RAW" | grep -iE 'error|warning|failed|success|complete|done|built|passed|summary:' | head -n 30)
        
        # Also capture the last 10 lines (often contains summary)
        STDOUT_TAIL=$(echo "$STDOUT_RAW" | tail -n 10)
        
        # If build succeeded, just show completion message
        if [[ "$EXIT_CODE" == "0" ]] && [[ $STDOUT_SIZE -gt $SIZE_THRESHOLD ]]; then
            STDOUT_FINAL="$SUMMARY_HEADER

=== Build Output Summary ===
$(echo "$STDOUT_SUMMARY" | head -n 10)

=== Final Output ===
$STDOUT_TAIL"
        else
            # For failures, show more context
            STDOUT_FINAL="$SUMMARY_HEADER

=== Key Messages ===
$STDOUT_SUMMARY

=== Final Output ===
$STDOUT_TAIL"
        fi
    else
        STDOUT_FINAL="$STDOUT_RAW"
    fi
    
    # Process stderr similarly
    if [[ $STDERR_SIZE -gt 1000 ]]; then
        STDERR_SUMMARY=$(echo "$STDERR_RAW" | grep -iE 'error|warning|fatal|panic|exception' | head -n 20)
        STDERR_FINAL="$SUMMARY_HEADER

=== Error Summary ===
$STDERR_SUMMARY"
    else
        STDERR_FINAL="$STDERR_RAW"
    fi
    
    # Save full output to artifacts if it's really large
    if [[ $TOTAL_SIZE -gt 50000 ]]; then
        ARTIFACT_DIR="docs/ci-status/build-logs"
        mkdir -p "$ARTIFACT_DIR"
        TIMESTAMP=$(date +%Y%m%d-%H%M%S)
        ARTIFACT_FILE="$ARTIFACT_DIR/${TIMESTAMP}-$(echo "$COMMAND" | tr ' /' '_-' | head -c 50).log"
        
        {
            echo "=== Command: $COMMAND ==="
            echo "=== Exit Code: $EXIT_CODE ==="
            echo "=== STDOUT ==="
            echo "$STDOUT_RAW"
            echo "=== STDERR ==="
            echo "$STDERR_RAW"
        } > "$ARTIFACT_FILE"
        
        # Add reference to full log in summary
        STDOUT_FINAL="$STDOUT_FINAL

[Full output saved to: $ARTIFACT_FILE]"
        
        # Log the summarization (skip if status-append.py not working)
        if [[ -x "ci/scripts/status-append.py" ]] || command -v status-append.py &>/dev/null; then
            python3 ci/scripts/status-append.py "output_summarized" \
                "{\"command\": \"$(echo "$COMMAND" | jq -Rs .)\", \"original_size\": $TOTAL_SIZE, \"artifact\": \"$ARTIFACT_FILE\"}" 2>/dev/null || true
        fi
    fi
    
    # Calculate and report bytes saved
    SUMMARIZED_SIZE=$(($(echo -n "$STDOUT_FINAL" | wc -c) + $(echo -n "$STDERR_FINAL" | wc -c)))
    BYTES_SAVED=$((TOTAL_SIZE - SUMMARIZED_SIZE))
    
    # Emit StatsD metric if available
    if command -v nc &>/dev/null && [[ -n "${STATSD_HOST:-}" ]]; then
        echo "build_log_bytes_saved:$BYTES_SAVED|c" | nc -w1 -u "${STATSD_HOST}" "${STATSD_PORT:-8125}" 2>/dev/null || true
    fi
    
    # Also log to our metrics file for local analysis
    if [[ $BYTES_SAVED -gt 0 ]]; then
        METRICS_FILE="docs/ci-status/metrics/summarizer-$(date +%Y%m).jsonl"
        mkdir -p "$(dirname "$METRICS_FILE")"
        echo "{\"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"command\": \"$COMMAND\", \"original_size\": $TOTAL_SIZE, \"summarized_size\": $SUMMARIZED_SIZE, \"bytes_saved\": $BYTES_SAVED, \"savings_pct\": $(( (BYTES_SAVED * 100) / TOTAL_SIZE ))}" >> "$METRICS_FILE"
    fi
    
    # Reconstruct the payload with summarized output
    echo "$PAYLOAD" | jq \
        --arg stdout "$STDOUT_FINAL" \
        --arg stderr "$STDERR_FINAL" \
        '.tool_response.stdout = $stdout | .tool_response.stderr = $stderr'
else
    # Output is small enough, pass through unchanged
    echo "$PAYLOAD"
fi