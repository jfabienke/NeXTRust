#!/usr/bin/env bash
# ci/scripts/gemini-cli-wrapper.sh - Wrapper for Gemini CLI with fallback
#
# Purpose: Provides a consistent interface for Gemini reviews regardless of CLI availability
# Usage: source this script and call gemini_review with prompt file
#
set -uo pipefail

# Source error handling utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gemini-error-handler.sh"

# Check if Gemini CLI is available and configured
check_gemini_cli() {
    if ! command -v gemini &> /dev/null; then
        echo "[$(date)] Gemini CLI not found in PATH"
        return 1
    fi
    
    # Perform health check if not done recently
    local health_cache="/tmp/gemini-health-cache"
    local cache_age=3600  # 1 hour
    
    if [[ -f "$health_cache" ]]; then
        local last_check=$(stat -f %m "$health_cache" 2>/dev/null || stat -c %Y "$health_cache" 2>/dev/null || echo 0)
        local now=$(date +%s)
        local age=$((now - last_check))
        
        if [[ $age -lt $cache_age ]]; then
            return 0  # Recent health check passed
        fi
    fi
    
    # Perform health check
    if check_gemini_health; then
        touch "$health_cache"
        return 0
    else
        rm -f "$health_cache"
        return 1
    fi
}

# Main review function that handles CLI vs API
gemini_review() {
    local prompt_file=$1
    local phase_id=${2:-"unknown"}
    local output_format=${3:-"json"}  # json or text
    
    if check_gemini_cli; then
        gemini_review_cli "$prompt_file" "$output_format"
    else
        gemini_review_api "$prompt_file" "$phase_id" "$output_format"
    fi
}

# Review using Gemini CLI
gemini_review_cli() {
    local prompt_file=$1
    local output_format=$2
    
    echo "[$(date)] Using Gemini CLI for review..."
    
    # Check prompt size before sending
    if ! check_prompt_size "$prompt_file"; then
        echo "⚠️  Prompt may be too large, proceeding anyway..."
    fi
    
    # Track prompt size for usage logging
    local prompt_size=$(wc -c < "$prompt_file")
    
    local cli_args=(
        --model gemini-2.5-pro
        --temperature 0.2
        -f "$prompt_file"
    )
    
    if [[ "$output_format" == "json" ]]; then
        cli_args+=(--json)
    fi
    
    # Use error-handling wrapper
    local temp_output="/tmp/gemini-output-$$"
    if execute_gemini_with_retry "${cli_args[@]}" > "$temp_output" 2>&1; then
        cat "$temp_output"
        local response_size=$(wc -c < "$temp_output")
        log_gemini_usage "$prompt_size" "$response_size" "true"
        rm -f "$temp_output"
        return 0
    else
        local exit_code=$?
        echo "❌ Gemini CLI review failed"
        cat "$temp_output" >&2
        log_gemini_usage "$prompt_size" "0" "false" "CLI_ERROR"
        rm -f "$temp_output"
        
        # Try fallback
        if gemini_fallback_handler "$prompt_file" "error"; then
            gemini_review_api "$prompt_file" "fallback" "$output_format"
        else
            return $exit_code
        fi
    fi
}

# Fallback to API method
gemini_review_api() {
    local prompt_file=$1
    local phase_id=$2
    local output_format=$3
    
    echo "[$(date)] Using Gemini API fallback..."
    
    # Check if API is configured
    if [[ -z "${GEMINI_API_KEY:-}" ]]; then
        echo "⚠️  Neither Gemini CLI nor API key found."
        echo "    Install CLI: pip install google-generativeai"
        echo "    Or set GEMINI_API_KEY environment variable"
        return 1
    fi
    
    # Read prompt content
    local prompt_content=$(cat "$prompt_file")
    
    # Build API request
    local api_request=$(jq -n \
        --arg prompt "$prompt_content" \
        --arg model "gemini-pro" \
        '{
            contents: [{
                parts: [{
                    text: $prompt
                }]
            }],
            generationConfig: {
                temperature: 0.2,
                maxOutputTokens: 2048
            }
        }')
    
    # Call Google AI API
    local api_url="https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent"
    local temp_response="/tmp/gemini-api-response-$$"
    local http_code=$(curl -s -w "%{http_code}" -X POST "$api_url" \
        -H "Content-Type: application/json" \
        -H "x-goog-api-key: $GEMINI_API_KEY" \
        -d "$api_request" \
        -o "$temp_response")
    
    local response=$(cat "$temp_response")
    rm -f "$temp_response"
    
    # Check HTTP status
    if [[ "$http_code" != "200" ]]; then
        echo "❌ Gemini API error (HTTP $http_code)"
        
        # Parse error response
        local error_message=$(echo "$response" | jq -r '.error.message // "Unknown error"' 2>/dev/null)
        echo "   Error: $error_message"
        
        # Log API error
        log_gemini_usage "${#prompt_content}" "0" "false" "API_ERROR_$http_code"
        
        # Handle specific error codes
        case "$http_code" in
            429)
                echo "   Rate limit exceeded. Free tier: 60 requests/min"
                ;;
            401|403)
                echo "   Authentication failed. Check GEMINI_API_KEY"
                ;;
            400)
                echo "   Invalid request. Check prompt format"
                ;;
            *)
                echo "   Response: $response"
                ;;
        esac
        return 1
    fi
    
    # Log successful API usage
    local response_size=${#response}
    log_gemini_usage "${#prompt_content}" "$response_size" "true"
    
    # Format response based on output format
    if [[ "$output_format" == "json" ]]; then
        echo "$response"
    else
        echo "$response" | jq -r '.candidates[0].content.parts[0].text // "No response"'
    fi
}

# Extract review content from Gemini response
extract_gemini_content() {
    local response=$1
    local provider=${2:-"unknown"}
    
    # Try different JSON paths based on provider
    local content=""
    
    if [[ "$provider" == "cli" ]]; then
        # Gemini CLI output format
        content=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // .content // empty' 2>/dev/null)
    else
        # API output format
        content=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)
    fi
    
    # Fallback to raw response if no structured content found
    if [[ -z "$content" ]]; then
        content="$response"
    fi
    
    echo "$content"
}

# Post-process review for GitHub formatting
format_review_for_github() {
    local content=$1
    local phase_name=${2:-"Unknown Phase"}
    
    # Extract GEMINI.md version
    local gemini_version="unknown"
    if [[ -f "GEMINI.md" ]]; then
        gemini_version=$(grep -E "^<!-- GEMINI-VERSION: .+ -->$" GEMINI.md | sed -E "s/<!-- GEMINI-VERSION: (.+) -->/\1/" || echo "unknown")
    fi
    
    cat << EOF
## 🤖 Gemini Code Review

**Phase**: $phase_name  
**Timestamp**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")  
**Guidelines Version**: GEMINI.md v$gemini_version

<details>
<summary>Click to expand review details</summary>

$content

</details>

---
*Generated by Gemini 2.5 Pro • [Review Guidelines](GEMINI.md)*
EOF
}

# Utility: Check token count (approximate)
estimate_token_count() {
    local file=$1
    # Rough estimate: 1 token ≈ 4 characters
    local chars=$(wc -c < "$file")
    echo $((chars / 4))
}

# Utility: Split large prompts if needed
check_prompt_size() {
    local prompt_file=$1
    local max_tokens=${2:-200000}  # Conservative limit
    
    local estimated_tokens=$(estimate_token_count "$prompt_file")
    
    if [[ $estimated_tokens -gt $max_tokens ]]; then
        echo "⚠️  Warning: Prompt may exceed token limit (~$estimated_tokens tokens)"
        echo "    Consider using more specific file selections"
        return 1
    fi
    
    return 0
}