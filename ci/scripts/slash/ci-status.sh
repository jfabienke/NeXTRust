#!/usr/bin/env bash
# ---
# argument-hint: ""
# ---
# ci/scripts/slash/ci-status.sh - Display pipeline status
#
# Purpose: Show current CI pipeline status from pipeline-log.md
# Usage: /ci-status

source ci/scripts/slash/common.sh

# Check if status file exists
STATUS_FILE="docs/ci-status/pipeline-log.md"

if [[ ! -f "$STATUS_FILE" ]]; then
    post_error "No pipeline status found. The pipeline may not have run yet."
    exit 1
fi

# Read status file (limit to 4000 chars for GitHub comment limit)
STATUS_CONTENT=$(head -c 4000 "$STATUS_FILE")

# Check if content was truncated
FILE_SIZE=$(wc -c < "$STATUS_FILE")
if [[ $FILE_SIZE -gt 4000 ]]; then
    STATUS_CONTENT="${STATUS_CONTENT}

*... truncated (showing first 4000 characters of $FILE_SIZE total)*"
fi

# Format response
RESPONSE="## 📊 CI Pipeline Status

$STATUS_CONTENT

---
*Use \`/ci-check-phase\` for detailed phase information*"

# Post response
post_response "$RESPONSE"

# Log successful command
log_command "success"