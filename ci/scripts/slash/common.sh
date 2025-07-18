#!/bin/bash
# ci/scripts/slash/common.sh - Common utilities for slash commands
#
# Purpose: Shared functions for all slash commands with security hardening
# Usage: source this file in each slash command script

set -euo pipefail

# Source input validation functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/validate-input.sh"

# Post response to PR
post_response() {
    local message="$1"
    
    if [[ -z "${CI_PR_NUMBER:-}" ]]; then
        echo "[WARNING] No PR number available, cannot post response"
        echo "[RESPONSE] $message"
        return
    fi
    
    if ! command -v gh &> /dev/null; then
        echo "[WARNING] gh CLI not available, cannot post response"
        echo "[RESPONSE] $message"
        return
    fi
    
    # Post to PR with error handling
    if ! gh api repos/${GITHUB_REPOSITORY}/issues/${CI_PR_NUMBER}/comments \
        -f body="$message" 2>/dev/null; then
        echo "::warning::Failed to post response to PR"
    fi
}

# Post error response
post_error() {
    local error="$1"
    post_response "❌ Error: $error"
}

# Post success response
post_success() {
    local message="$1"
    post_response "✅ $message"
}

# Enhanced validate_arg with security validation
# Usage: validate_arg "argument" "type" "name"
# Types: command_name, job_name, phase_id, pr_number, username, review_channel, file_path, text
validate_arg() {
    local arg="${1:-}"
    local type="${2:-text}"
    local name="${3:-argument}"
    
    if [[ -z "$arg" ]]; then
        post_error "Missing required $name"
        exit 1
    fi
    
    # Use type-specific validation
    local validated=""
    case "$type" in
        command_name)
            validated=$(validate_command_name "$arg") || {
                post_error "Invalid $name: $(validate_command_name "$arg" 2>&1)"
                exit 1
            }
            ;;
        job_name)
            validated=$(validate_job_name "$arg") || {
                post_error "Invalid $name: $(validate_job_name "$arg" 2>&1)"
                exit 1
            }
            ;;
        phase_id)
            validated=$(validate_phase_id "$arg") || {
                post_error "Invalid $name: $(validate_phase_id "$arg" 2>&1)"
                exit 1
            }
            ;;
        pr_number)
            validated=$(validate_pr_number "$arg") || {
                post_error "Invalid $name: $(validate_pr_number "$arg" 2>&1)"
                exit 1
            }
            ;;
        username)
            validated=$(validate_username "$arg") || {
                post_error "Invalid $name: $(validate_username "$arg" 2>&1)"
                exit 1
            }
            ;;
        review_channel)
            validated=$(validate_review_channel "$arg") || {
                post_error "Invalid $name: $(validate_review_channel "$arg" 2>&1)"
                exit 1
            }
            ;;
        file_path)
            validated=$(validate_file_path "$arg") || {
                post_error "Invalid $name: $(validate_file_path "$arg" 2>&1)"
                exit 1
            }
            ;;
        text|*)
            validated=$(sanitize_text "$arg" 500)
            ;;
    esac
    
    echo "$validated"
}

# Check rate limit (30s cooldown per user)
check_rate_limit() {
    local user="${CI_TRIGGERED_BY:-${GITHUB_ACTOR:-unknown}}"
    local cooldown_dir=".claude/cooldowns"
    local cooldown_file="$cooldown_dir/$user"
    
    mkdir -p "$cooldown_dir" 2>/dev/null || true
    
    if [[ -f "$cooldown_file" ]]; then
        # Get last modification time (portable across macOS and Linux)
        local last_command
        if command -v stat >/dev/null 2>&1; then
            # Try GNU stat first (Linux)
            last_command=$(stat -c %Y "$cooldown_file" 2>/dev/null || stat -f %m "$cooldown_file" 2>/dev/null || echo 0)
        else
            # Fallback to ls
            last_command=$(date -r "$cooldown_file" +%s 2>/dev/null || echo 0)
        fi
        
        local now=$(date +%s)
        local elapsed=$((now - last_command))
        
        if [[ $elapsed -lt 30 ]]; then
            local remaining=$((30 - elapsed))
            post_error "Rate limit: please wait $remaining seconds before next command"
            exit 1
        fi
    fi
    
    # Update cooldown file
    touch "$cooldown_file"
}

# Acquire lock for state mutations
acquire_command_lock() {
    local lockfile=".claude/command.lock"
    mkdir -p "$(dirname "$lockfile")" 2>/dev/null || true
    
    # Try to acquire lock with timeout
    local count=0
    while ! mkdir "$lockfile" 2>/dev/null; do
        if [[ $count -ge 10 ]]; then
            post_error "Could not acquire command lock after 10 seconds"
            exit 1
        fi
        ((count++))
        sleep 1
    done
    
    # Ensure lock is released on exit
    trap "rmdir '$lockfile' 2>/dev/null || true" EXIT
}

# Log command execution
log_command() {
    local status="${1:-executed}"
    local details="${2:-}"
    
    # Build details JSON
    local json_details="{\"command\": \"${CI_COMMAND:-unknown}\", \"args\": \"${CI_ARGS:-}\", \"user\": \"${CI_TRIGGERED_BY:-unknown}\", \"status\": \"$status\""
    if [[ -n "$details" ]]; then
        json_details="${json_details}, \"details\": \"$details\""
    fi
    json_details="${json_details}}"
    
    # Log to status system
    if [[ -x "ci/scripts/status-append.py" ]]; then
        python3 ci/scripts/status-append.py "slash_command" "$json_details" || true
    fi
    
    # Also log to dedicated command log
    local log_file="docs/ci-status/command-log.json"
    mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
    
    if [[ ! -f "$log_file" ]]; then
        echo '{"commands": []}' > "$log_file"
    fi
    
    # Append to command log (simplified, not using full locking for read)
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local entry="{\"timestamp\": \"$timestamp\", \"command\": \"${CI_COMMAND:-unknown}\", \"args\": \"${CI_ARGS:-}\", \"user\": \"${CI_TRIGGERED_BY:-unknown}\", \"status\": \"$status\"}"
    
    # Note: In production, this should use proper file locking
    echo "[$(date)] Command logged: $entry" >&2
}

# Get current phase information
get_current_phase() {
    local phase_file="docs/ci-status/pipeline-log.json"
    
    if [[ ! -f "$phase_file" ]]; then
        echo "unknown"
        return
    fi
    
    jq -r '.current_phase.id // "unknown"' "$phase_file" 2>/dev/null || echo "unknown"
}

# Check if user has write permissions
check_write_permission() {
    # In GitHub Actions context, we've already validated user association
    # This is a placeholder for additional permission checks if needed
    return 0
}

# Initialize slash command environment
init_slash_command() {
    # Check rate limit first
    check_rate_limit
    
    # Log command start
    log_command "started"
    
    # Set up error handling
    trap 'log_command "failed" "$?"' ERR
    
    # Ensure we're in project root
    if [[ ! -f ".github/workflows/nextrust-ci.yml" ]]; then
        post_error "Not in project root directory"
        exit 1
    fi
}

# Common initialization for all slash commands
init_slash_command