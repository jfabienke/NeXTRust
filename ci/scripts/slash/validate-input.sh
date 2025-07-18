#!/usr/bin/env bash
# ci/scripts/slash/validate-input.sh - Input validation for slash commands
#
# Purpose: Sanitize and validate inputs to prevent injection attacks
# Usage: source this file and use validate_* functions
#
set -uo pipefail

# Validate command name (alphanumeric with hyphens only)
validate_command_name() {
    local input="$1"
    
    # Check length
    if [[ ${#input} -gt 50 ]]; then
        echo "Error: Command name too long (max 50 chars)" >&2
        return 1
    fi
    
    # Check pattern
    if [[ ! "$input" =~ ^[a-zA-Z0-9-]+$ ]]; then
        echo "Error: Invalid command name. Use only alphanumeric and hyphens." >&2
        return 1
    fi
    
    echo "$input"
}

# Validate job name (alphanumeric, hyphens, dots)
validate_job_name() {
    local input="$1"
    
    # Check length
    if [[ ${#input} -gt 100 ]]; then
        echo "Error: Job name too long (max 100 chars)" >&2
        return 1
    fi
    
    # Check pattern
    if [[ ! "$input" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        echo "Error: Invalid job name. Use only alphanumeric, dots, and hyphens." >&2
        return 1
    fi
    
    echo "$input"
}

# Validate phase ID
validate_phase_id() {
    local input="$1"
    
    # Check length
    if [[ ${#input} -gt 20 ]]; then
        echo "Error: Phase ID too long (max 20 chars)" >&2
        return 1
    fi
    
    # Check pattern (phase-N format)
    if [[ ! "$input" =~ ^phase-[0-9]+$ ]]; then
        echo "Error: Invalid phase ID. Use format: phase-N" >&2
        return 1
    fi
    
    echo "$input"
}

# Validate PR number
validate_pr_number() {
    local input="$1"
    
    # Check if numeric
    if [[ ! "$input" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid PR number. Must be numeric." >&2
        return 1
    fi
    
    # Check reasonable range
    if [[ $input -lt 1 || $input -gt 999999 ]]; then
        echo "Error: PR number out of range (1-999999)" >&2
        return 1
    fi
    
    echo "$input"
}

# Validate username
validate_username() {
    local input="$1"
    
    # Check length
    if [[ ${#input} -gt 39 ]]; then
        echo "Error: Username too long (max 39 chars)" >&2
        return 1
    fi
    
    # GitHub username pattern
    if [[ ! "$input" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
        echo "Error: Invalid username format" >&2
        return 1
    fi
    
    echo "$input"
}

# Validate review channel (gemini/o3)
validate_review_channel() {
    local input="$1"
    
    case "$input" in
        gemini|o3)
            echo "$input"
            ;;
        *)
            echo "Error: Invalid review channel. Use 'gemini' or 'o3'." >&2
            return 1
            ;;
    esac
}

# Sanitize general text input (for messages, descriptions)
sanitize_text() {
    local input="$1"
    local max_length="${2:-500}"
    
    # Truncate to max length
    if [[ ${#input} -gt $max_length ]]; then
        input="${input:0:$max_length}..."
    fi
    
    # Remove control characters (including ANSI escape sequences) and escape quotes
    # Using perl for better escape sequence handling
    local sanitized
    if command -v perl &>/dev/null; then
        sanitized=$(printf '%s' "$input" | perl -pe 's/[\x00-\x1F\x7F]//g; s/\e\[[0-9;]*m//g; s/["\x27]/\\$&/g')
    else
        # Fallback to basic sed/tr
        sanitized=$(printf '%s' "$input" | tr -d '\000-\037\177' | sed -e $'s/\033\\[[0-9;]*m//g' -e "s/[\"']/\\\&/g")
    fi
    
    echo "$sanitized"
}

# Validate file path (no traversal)
validate_file_path() {
    local input="$1"
    
    # Check for path traversal attempts
    if [[ "$input" == *".."* ]] || [[ "$input" == *"~"* ]]; then
        echo "Error: Path traversal not allowed" >&2
        return 1
    fi
    
    # Check for absolute paths
    if [[ "$input" == /* ]]; then
        echo "Error: Absolute paths not allowed" >&2
        return 1
    fi
    
    # Check length
    if [[ ${#input} -gt 255 ]]; then
        echo "Error: Path too long (max 255 chars)" >&2
        return 1
    fi
    
    # Only allow safe characters
    if [[ ! "$input" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
        echo "Error: Invalid characters in path" >&2
        return 1
    fi
    
    echo "$input"
}

# Validate arguments array (space-separated)
validate_arguments() {
    local input="$1"
    
    # Check total length
    if [[ ${#input} -gt 1000 ]]; then
        echo "Error: Arguments too long (max 1000 chars)" >&2
        return 1
    fi
    
    # Split and validate each argument
    local args=()
    for arg in $input; do
        # Skip empty
        [[ -z "$arg" ]] && continue
        
        # Basic sanitization
        local clean_arg=$(echo "$arg" | tr -d '\000-\037' | sed 's/[;&|<>$`\\]//g')
        args+=("$clean_arg")
    done
    
    echo "${args[@]}"
}

# Main validation dispatcher
validate_slash_input() {
    local command="$1"
    local args="${2:-}"
    
    # Validate command first
    local valid_command=$(validate_command_name "$command") || return 1
    
    # Command-specific validation
    case "$valid_command" in
        ci-retry-job)
            validate_job_name "$args" || return 1
            ;;
        ci-reset-phase)
            validate_phase_id "$args" || return 1
            ;;
        ci-force-review)
            validate_review_channel "$args" || return 1
            ;;
        ci-get-logs)
            validate_job_name "$args" || return 1
            ;;
        *)
            # Generic argument validation
            validate_arguments "$args" || return 1
            ;;
    esac
    
    return 0
}