#!/usr/bin/env bash
# ci/scripts/add-argument-hints.sh - Add argument-hint metadata to slash commands
#
# Purpose: Update all slash command scripts with appropriate argument hints
# Usage: ./ci/scripts/add-argument-hints.sh
#
set -uo pipefail

echo "Adding argument hints to slash commands..."

# Function to add hint to a file
add_hint() {
    local script="$1"
    local hint="$2"
    local basename=$(basename "$script")
    
    # Skip if already has argument-hint
    if grep -q "^# argument-hint:" "$script" 2>/dev/null; then
        echo "✓ $basename already has argument-hint"
        return 0
    fi
    
    # Create temporary file
    tmpfile=$(mktemp)
    
    # Read the first line (shebang)
    head -1 "$script" > "$tmpfile"
    
    # Add argument-hint block
    cat >> "$tmpfile" << EOF
# ---
# argument-hint: "$hint"
# ---
EOF
    
    # Add the rest of the file (skip first line)
    tail -n +2 "$script" >> "$tmpfile"
    
    # Replace original file
    mv "$tmpfile" "$script"
    chmod +x "$script"
    
    echo "✅ Added argument-hint to $basename: ${hint:-'(no arguments)'}"
}

# Process each command with its specific hint
add_hint "ci/scripts/slash/ci-retry-job.sh" "<job-name>"
add_hint "ci/scripts/slash/ci-reset-phase.sh" "<phase-id>"
add_hint "ci/scripts/slash/ci-get-logs.sh" "<job-name>"
add_hint "ci/scripts/slash/ci-force-review.sh" "o3|gemini"
add_hint "ci/scripts/slash/ci-clear-cache.sh" ""
add_hint "ci/scripts/slash/ci-clear-backoff.sh" ""
add_hint "ci/scripts/slash/ci-status.sh" ""
add_hint "ci/scripts/slash/ci-check-phase.sh" ""
add_hint "ci/scripts/slash/ci-help.sh" ""

echo
echo "All slash commands updated with argument hints!"