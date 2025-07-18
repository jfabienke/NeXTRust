#!/usr/bin/env bash
# ci/scripts/check-ccusage.sh - Comprehensive ccusage availability checker
#
# Purpose: Check if ccusage (https://github.com/ryoppippi/ccusage) is available
# This tool analyzes Claude Code's local JSONL files for token usage and costs
# Usage: source this script or run directly
#
set -uo pipefail

# Function to check ccusage availability
check_ccusage_availability() {
    local verbose="${1:-false}"
    
    # Check if ccusage command exists
    if ! command -v ccusage &>/dev/null; then
        [[ "$verbose" == "true" ]] && echo "❌ ccusage command not found in PATH"
        return 1
    fi
    
    # Check if we can get version
    local version
    version=$(ccusage --version 2>&1 || echo "unknown")
    if [[ "$version" == "unknown" ]] || [[ "$version" =~ "error" ]]; then
        [[ "$verbose" == "true" ]] && echo "❌ ccusage installed but not responding properly"
        return 2
    fi
    
    # Check if Claude Code is running (by checking for session ID)
    if [[ -z "${CCODE_SESSION_ID:-}" ]] && [[ "$verbose" == "true" ]]; then
        echo "⚠️  No active Claude Code session detected (CCODE_SESSION_ID not set)"
        echo "   ccusage will only work within Claude Code sessions"
    fi
    
    # Check minimum version requirement (1.0.55+)
    local min_version="1.0.55"
    if command -v sort &>/dev/null; then
        local sorted_version=$(printf '%s\n%s' "$min_version" "$version" | sort -V | head -1)
        if [[ "$sorted_version" != "$min_version" ]] && [[ "$verbose" == "true" ]]; then
            echo "⚠️  ccusage version $version is older than recommended $min_version"
            echo "   Some features may not work correctly"
        fi
    fi
    
    [[ "$verbose" == "true" ]] && echo "✅ ccusage v$version is available"
    return 0
}

# Function to ensure ccusage is available or skip gracefully
ensure_ccusage_or_skip() {
    if ! check_ccusage_availability false; then
        echo "[$(date)] ccusage not available - skipping token tracking" >&2
        return 1
    fi
    return 0
}

# Function to test ccusage with a simple command
test_ccusage_functionality() {
    echo "Testing ccusage functionality..."
    
    # Try to get usage for current or test session
    local test_session="${CCODE_SESSION_ID:-test-session}"
    local test_output
    
    echo -n "  Getting usage for session $test_session... "
    if test_output=$(timeout 5s ccusage --session-id "$test_session" --format json 2>&1); then
        echo "✅ Success"
        
        # Validate JSON output
        echo -n "  Validating JSON output... "
        if echo "$test_output" | jq -e . >/dev/null 2>&1; then
            echo "✅ Valid JSON"
            
            # Check for expected fields
            echo -n "  Checking for required fields... "
            local has_tokens=$(echo "$test_output" | jq -e '.total_tokens' >/dev/null 2>&1 && echo "yes" || echo "no")
            local has_model=$(echo "$test_output" | jq -e '.model' >/dev/null 2>&1 && echo "yes" || echo "no")
            
            if [[ "$has_tokens" == "yes" ]] && [[ "$has_model" == "yes" ]]; then
                echo "✅ All fields present"
            else
                echo "⚠️  Some fields missing"
            fi
        else
            echo "❌ Invalid JSON"
            echo "    Output: $test_output"
        fi
    else
        echo "❌ Failed"
        echo "    Error: $test_output"
    fi
}

# Function to check metrics directory
check_metrics_setup() {
    echo "Checking metrics setup..."
    
    local metrics_dir="docs/ci-status/metrics"
    echo -n "  Metrics directory exists... "
    if [[ -d "$metrics_dir" ]]; then
        echo "✅ Yes"
        
        # Check write permissions
        echo -n "  Write permissions... "
        if touch "$metrics_dir/.test" 2>/dev/null && rm -f "$metrics_dir/.test"; then
            echo "✅ OK"
        else
            echo "❌ No write permission"
        fi
        
        # Check for existing logs
        echo -n "  Existing usage logs... "
        local log_count=$(find "$metrics_dir" -name "token-usage-*.jsonl" 2>/dev/null | wc -l)
        if [[ $log_count -gt 0 ]]; then
            echo "✅ Found $log_count log file(s)"
        else
            echo "ℹ️  No logs yet"
        fi
    else
        echo "❌ Not found"
        echo "    Creating directory..."
        mkdir -p "$metrics_dir" && echo "    ✅ Created" || echo "    ❌ Failed to create"
    fi
}

# Main execution when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "=== ccusage Availability Check ==="
    echo
    
    # Run all checks
    check_ccusage_availability true
    echo
    
    if check_ccusage_availability false; then
        test_ccusage_functionality
        echo
        check_metrics_setup
        echo
        echo "Overall status: ✅ ccusage integration is ready"
    else
        echo "Overall status: ❌ ccusage not available"
        echo
        echo "To install ccusage:"
        echo "1. Ensure Claude Code is installed"
        echo "2. Update to the latest version"
        echo "3. Restart your terminal"
    fi
fi