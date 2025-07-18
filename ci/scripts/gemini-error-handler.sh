#!/usr/bin/env bash
# ci/scripts/gemini-error-handler.sh - Robust error handling for Gemini CLI
#
# Purpose: Handle various Gemini CLI failure modes gracefully
# Usage: source this file in scripts that use Gemini CLI
#
set -uo pipefail

# Error codes
readonly GEMINI_ERROR_AUTH=1
readonly GEMINI_ERROR_RATE_LIMIT=2
readonly GEMINI_ERROR_NETWORK=3
readonly GEMINI_ERROR_TIMEOUT=4
readonly GEMINI_ERROR_INVALID_INPUT=5
readonly GEMINI_ERROR_UNKNOWN=99

# Parse Gemini CLI error output
parse_gemini_error() {
    local stderr_output="$1"
    local exit_code="${2:-1}"
    
    # Check for common error patterns (case insensitive)
    local stderr_lower=$(echo "$stderr_output" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$stderr_lower" =~ "not authenticated" ]] || [[ "$stderr_lower" =~ "authentication" ]]; then
        echo "AUTH_ERROR"
        return $GEMINI_ERROR_AUTH
    elif [[ "$stderr_lower" =~ "rate limit" ]] || [[ "$stderr_lower" =~ "quota exceeded" ]]; then
        echo "RATE_LIMIT"
        return $GEMINI_ERROR_RATE_LIMIT
    elif [[ "$stderr_lower" =~ "network" ]] || [[ "$stderr_lower" =~ "connection" ]] || [[ "$stderr_lower" =~ "timeout" ]]; then
        echo "NETWORK_ERROR"
        return $GEMINI_ERROR_NETWORK
    elif [[ "$exit_code" -eq 124 ]]; then
        echo "TIMEOUT"
        return $GEMINI_ERROR_TIMEOUT
    elif [[ "$stderr_lower" =~ "invalid" ]] || [[ "$stderr_lower" =~ "malformed" ]]; then
        echo "INVALID_INPUT"
        return $GEMINI_ERROR_INVALID_INPUT
    else
        echo "UNKNOWN_ERROR"
        return $GEMINI_ERROR_UNKNOWN
    fi
}

# Handle specific error types
handle_gemini_error() {
    local error_type="$1"
    local error_output="${2:-}"
    local retry_count="${3:-0}"
    
    case "$error_type" in
        AUTH_ERROR)
            echo "❌ Gemini authentication failed"
            echo "   Please run 'gemini' interactively to authenticate"
            echo "   Or set GEMINI_API_KEY environment variable"
            return 1
            ;;
        RATE_LIMIT)
            echo "⏱️  Gemini rate limit exceeded (1000/day, 60/min)"
            if [[ $retry_count -lt 3 ]]; then
                echo "   Waiting 60 seconds before retry..."
                sleep 60
                return 0  # Indicate retry is possible
            else
                echo "   Maximum retries exceeded"
                return 1
            fi
            ;;
        NETWORK_ERROR)
            echo "🌐 Network error communicating with Gemini"
            if [[ $retry_count -lt 2 ]]; then
                echo "   Retrying in 10 seconds..."
                sleep 10
                return 0  # Indicate retry is possible
            else
                echo "   Network appears to be down"
                return 1
            fi
            ;;
        TIMEOUT)
            echo "⏰ Gemini request timed out"
            echo "   Consider reducing prompt size or complexity"
            return 1
            ;;
        INVALID_INPUT)
            echo "❌ Invalid input provided to Gemini"
            echo "   Error: $error_output"
            return 1
            ;;
        UNKNOWN_ERROR)
            echo "❌ Unknown Gemini error"
            echo "   Error output: $error_output"
            echo "   Exit code: $?"
            return 1
            ;;
    esac
}

# Safe Gemini CLI execution with retries
execute_gemini_with_retry() {
    local max_retries=3
    local retry_count=0
    local temp_stderr="/tmp/gemini-stderr-$$"
    
    # Extract timeout if specified
    local timeout_seconds=300
    local timeout_cmd=""
    if command -v timeout &>/dev/null; then
        timeout_cmd="timeout $timeout_seconds"
    fi
    
    while [[ $retry_count -lt $max_retries ]]; do
        echo "[$(date)] Executing Gemini CLI (attempt $((retry_count + 1))/$max_retries)..."
        
        # Execute with error capture
        if $timeout_cmd gemini "$@" 2>"$temp_stderr"; then
            rm -f "$temp_stderr"
            return 0
        fi
        
        local exit_code=$?
        local stderr_content=$(cat "$temp_stderr" 2>/dev/null || echo "")
        
        # Parse and handle error
        local error_type=$(parse_gemini_error "$stderr_content" "$exit_code")
        
        # Log to failure tracking
        if [[ -f "hooks/dispatcher.d/common/failure-tracking-db.sh" ]]; then
            source hooks/dispatcher.d/common/failure-tracking-db.sh
            increment_failure_count_for_command "gemini $1"
        fi
        
        # Handle the error
        if ! handle_gemini_error "$error_type" "$stderr_content" "$retry_count"; then
            rm -f "$temp_stderr"
            return 1
        fi
        
        ((retry_count++))
    done
    
    rm -f "$temp_stderr"
    echo "❌ Maximum retries ($max_retries) exceeded for Gemini CLI"
    return 1
}

# Check Gemini CLI health
check_gemini_health() {
    local temp_file="/tmp/gemini-health-check-$$"
    local temp_stderr="/tmp/gemini-health-stderr-$$"
    
    echo "[$(date)] Checking Gemini CLI health..."
    
    # Try a simple prompt
    if timeout 30 gemini "What is 2+2?" > "$temp_file" 2>"$temp_stderr"; then
        if grep -q "4" "$temp_file"; then
            echo "✅ Gemini CLI is working correctly"
            rm -f "$temp_file" "$temp_stderr"
            return 0
        else
            echo "⚠️  Gemini CLI returned unexpected output"
            cat "$temp_file"
        fi
    else
        echo "❌ Gemini CLI health check failed"
        cat "$temp_stderr"
    fi
    
    rm -f "$temp_file" "$temp_stderr"
    return 1
}

# Log Gemini usage for tracking
log_gemini_usage() {
    local prompt_size="$1"
    local response_size="${2:-0}"
    local success="${3:-false}"
    local error_type="${4:-}"
    
    local usage_log="docs/ci-status/metrics/gemini-usage.jsonl"
    mkdir -p "$(dirname "$usage_log")"
    
    local usage_entry=$(jq -cn \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg prompt_size "$prompt_size" \
        --arg response_size "$response_size" \
        --arg success "$success" \
        --arg error_type "$error_type" \
        '{
            timestamp: $timestamp,
            prompt_size: ($prompt_size | tonumber),
            response_size: ($response_size | tonumber),
            success: ($success == "true"),
            error_type: $error_type,
            model: "gemini-2.5-pro",
            mode: "cli"
        }')
    
    echo "$usage_entry" >> "$usage_log"
}

# Fallback handler when Gemini is unavailable
gemini_fallback_handler() {
    local prompt_file="$1"
    local reason="${2:-unavailable}"
    
    echo "⚠️  Gemini CLI is $reason, checking fallback options..."
    
    # Check for API key
    if [[ -n "${GEMINI_API_KEY:-}" ]]; then
        echo "   Using Gemini API as fallback"
        return 0
    fi
    
    # Check for alternative AI services
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        echo "   Consider using O3 for this request"
        return 2
    fi
    
    echo "❌ No fallback options available"
    echo "   Please either:"
    echo "   1. Install and authenticate Gemini CLI"
    echo "   2. Set GEMINI_API_KEY environment variable"
    echo "   3. Configure alternative AI service (O3)"
    return 1
}