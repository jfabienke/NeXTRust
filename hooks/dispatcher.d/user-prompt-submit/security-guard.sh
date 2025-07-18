#!/bin/bash
# hooks/dispatcher.d/user-prompt-submit/security-guard.sh
#
# Purpose: Block destructive commands before execution
# Triggered by: UserPromptSubmit hook
#
set -euo pipefail

# Extract prompt from JSON payload
PROMPT=$(echo "$PAYLOAD" | jq -r '.prompt // ""' 2>/dev/null || echo "")

# Define forbidden patterns
FORBIDDEN_PATTERNS=(
    'rm -rf'
    ':(){:|:&};:'  # fork-bomb
    'dd if=/dev/zero'
    'mkfs'
    '> /dev/sda'
    'chmod -R 777 /'
)

# Check for destructive patterns
for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
    if [[ "$PROMPT" == *"$pattern"* ]]; then
        echo "::error::Destructive command blocked: contains '$pattern'"
        
        # Log the attempt
        python3 ci/scripts/status-append.py "security_block" \
            "{\"prompt\": \"$(echo "$PROMPT" | jq -Rs .)\", \"pattern\": \"$pattern\", \"user\": \"${USER:-unknown}\"}"
        
        exit 1
    fi
done

echo "[$(date)] Security check passed"