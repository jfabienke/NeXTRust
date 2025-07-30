#!/bin/bash
# hooks/dispatcher.d/common/failure-analysis.sh - Unified failure analysis
#
# Purpose: Provide common failure analysis functions for all hooks
# Source this file to access: analyze_failure(), capture_error_snapshot(), match_known_issue()
#
set -uo pipefail

# Analyze command failure and decide on recovery strategy
analyze_failure() {
    local command="$1"
    local exit_code="$2"
    local error_output="${3:-}"
    
    echo "[$(date)] Analyzing failure: Command='$command', Exit code=$exit_code"
    
    # Log the failure
    if command -v python3 &>/dev/null && [[ -x "ci/scripts/status-append.py" || -x "$(which status-append.py 2>/dev/null)" ]]; then
        python3 ci/scripts/status-append.py "build_failure" \
            "{\"command\": \"$command\", \"exit_code\": $exit_code, \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" 2>/dev/null || true
    fi
    
    # Check for known issues
    local match_result
    if match_result=$(match_known_issue "$error_output"); then
        echo "[$(date)] Matched known issue:"
        echo "$match_result"
        
        # Extract auto-fix if available
        local auto_fix_script=$(echo "$match_result" | jq -r '.auto_fix.script // empty' 2>/dev/null)
        if [[ -n "$auto_fix_script" && -x "$auto_fix_script" ]]; then
            echo "[$(date)] Applying auto-fix: $auto_fix_script"
            if command -v emit_counter &>/dev/null; then
                emit_counter "auto_fix.attempts" 1
            fi
            
            if "$auto_fix_script"; then
                echo "[$(date)] Auto-fix successful"
                return 0
            else
                echo "[$(date)] Auto-fix failed"
            fi
        fi
    fi
    
    # Check if this is a file-related error
    if is_file_error "$error_output"; then
        capture_error_snapshot "$command" "$error_output"
    fi
    
    # With O3 now 10x cheaper, consider escalating more failures
    # Escalate if:
    # 1. Not a known issue
    # 2. Failed more than twice
    # 3. Complex error pattern
    local failure_count=$(get_failure_count_for_command "$command" 2>/dev/null || echo 3)
    if [[ -z "$match_result" ]] && [[ $failure_count -gt 2 ]]; then
        echo "[$(date)] Considering O3 escalation (failure count: $failure_count)"
        
        # Check if error is complex enough for O3
        if should_escalate_to_o3 "$error_output"; then
            echo "[$(date)] Escalating to O3 for design guidance"
            if [[ -x "ci/scripts/request-ai-service.sh" ]]; then
                ./ci/scripts/request-ai-service.sh \
                    --service o3 \
                    --type design \
                    --context "Build failure: $command (exit $exit_code)" \
                    || echo "[$(date)] O3 escalation failed"
            fi
        fi
    fi
    
    return 1
}

# Capture shell snapshot for file-related errors
capture_error_snapshot() {
    local command="$1"
    local error_output="$2"
    
    echo "[$(date)] Capturing error snapshot for file-related error"
    
    # Extract file path from error
    local file_path=""
    if [[ "$error_output" =~ ([^[:space:]]+):[[:space:]]*(No such file|Permission denied|cannot open) ]]; then
        file_path="${BASH_REMATCH[1]}"
    elif [[ "$command" =~ (build\.log|test\.log|pipeline-log\.json) ]]; then
        file_path="${BASH_REMATCH[1]}"
    fi
    
    if [[ -z "$file_path" ]]; then
        echo "[$(date)] Could not extract file path from error"
        return 1
    fi
    
    # Create snapshot
    local snapshot_dir="docs/ci-status/snapshots"
    mkdir -p "$snapshot_dir"
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local snapshot_file="$snapshot_dir/error-${timestamp}.txt"
    
    {
        echo "=== Error Snapshot ==="
        echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Command: $command"
        echo "Error: $error_output"
        echo "File Path: $file_path"
        echo
        echo "=== Directory Listing ==="
        echo "PWD: $(pwd)"
        ls -la "$(dirname "$file_path")" 2>&1 || echo "Directory not accessible"
        echo
        echo "=== File Status ==="
        if [[ -e "$file_path" ]]; then
            echo "File exists"
            ls -la "$file_path" 2>&1
            echo "Type: $(file "$file_path" 2>&1)"
        else
            echo "File does not exist"
            echo "Parent directory: $(dirname "$file_path")"
            echo "Expected location: $(readlink -f "$file_path" 2>&1 || echo "$file_path")"
        fi
        echo
        echo "=== Environment ==="
        echo "USER: $USER"
        echo "HOME: $HOME"
        echo "CI: ${CI:-false}"
        echo "GITHUB_ACTIONS: ${GITHUB_ACTIONS:-false}"
    } > "$snapshot_file"
    
    echo "[$(date)] Snapshot saved to: $snapshot_file"
    
    # Rotate old snapshots
    if command -v bash &>/dev/null && [[ -x "ci/scripts/rotate-snapshots.sh" ]]; then
        bash ci/scripts/rotate-snapshots.sh 2>/dev/null || true
    fi
}

# Match error against known issues database
match_known_issue() {
    local error_output="$1"
    local context="${2:-}"
    
    local known_issues_file="docs/ci-status/known-issues.json"
    if [[ ! -f "$known_issues_file" ]]; then
        return 1
    fi
    
    # Use Python script if available for complex matching
    if command -v python3 &>/dev/null && [[ -x "ci/scripts/match-known-issue.py" ]]; then
        if [[ -n "$context" ]]; then
            python3 ci/scripts/match-known-issue.py "$error_output" "$context" 2>/dev/null
        else
            # Build context from environment
            local phase=$(jq -r '.current_phase.id // "unknown"' docs/ci-status/pipeline-log.json 2>/dev/null || echo "unknown")
            local cpu_variant="${CPU_VARIANT:-unknown}"
            context=$(jq -n \
                --arg phase "$phase" \
                --arg cpu "$cpu_variant" \
                --arg output "$error_output" \
                '{phase: $phase, cpu_variant: $cpu, full_output: $output}')
            python3 ci/scripts/match-known-issue.py "$error_output" "$context" 2>/dev/null
        fi
    else
        # Simple pattern matching fallback
        local matched_issue=""
        while IFS= read -r issue; do
            local pattern=$(echo "$issue" | jq -r '.pattern // empty' 2>/dev/null)
            if [[ -n "$pattern" ]] && [[ "$error_output" == *"$pattern"* ]]; then
                matched_issue="$issue"
                break
            fi
        done < <(jq -c '.issues[]' "$known_issues_file" 2>/dev/null)
        
        if [[ -n "$matched_issue" ]]; then
            echo "$matched_issue"
            return 0
        fi
    fi
    
    return 1
}

# Check if error is file-related
is_file_error() {
    local error_output="$1"
    
    local file_error_patterns=(
        "No such file or directory"
        "Permission denied"
        "cannot open"
        "build.log"
        "test.log"
        "pipeline-log.json"
    )
    
    for pattern in "${file_error_patterns[@]}"; do
        if [[ "$error_output" == *"$pattern"* ]]; then
            return 0
        fi
    done
    
    return 1
}

# Determine if error should be escalated to O3
should_escalate_to_o3() {
    local error_output="$1"
    
    # Complex error patterns that benefit from O3 design guidance
    local complex_patterns=(
        "undefined reference"
        "multiple definition"
        "cannot find -l"
        "relocation .* can not be used"
        "architecture .* is not supported"
        "LLVM ERROR:"
        "rustc.*internal compiler error"
        "cargo.*failed to compile"
        "atomics.*not supported"
        "target.*not found"
    )
    
    for pattern in "${complex_patterns[@]}"; do
        if [[ "$error_output" =~ $pattern ]]; then
            return 0  # Should escalate
        fi
    done
    
    # Check error length - very long errors often need design help
    if [[ ${#error_output} -gt 500 ]]; then
        return 0  # Should escalate
    fi
    
    return 1  # Don't escalate
}

# Source the failure tracking database
source "$(dirname "${BASH_SOURCE[0]}")/failure-tracking-db.sh"

# Source metrics if available
if [[ -f "hooks/dispatcher.d/common/metrics.sh" ]]; then
    source hooks/dispatcher.d/common/metrics.sh
fi