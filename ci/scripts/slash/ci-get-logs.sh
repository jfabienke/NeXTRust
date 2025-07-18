#!/usr/bin/env bash
# ---
# argument-hint: "<job-name>"
# ---
# ci/scripts/slash/ci-get-logs.sh - Get logs for a specific job
#
# Purpose: Retrieve and display logs for a specific CI job
# Usage: /ci-get-logs <job-name>

source ci/scripts/slash/common.sh

# Validate argument using type-specific validation
JOB_NAME=$(validate_arg "${CI_ARGS:-}" 'job_name' 'job name')

# Get workflow runs for current SHA
RUNS=$(gh api repos/${GITHUB_REPOSITORY}/actions/runs \
    --jq '.workflow_runs[] | select(.head_sha == env.GITHUB_SHA)' \
    -f status=completed \
    -f per_page=10 2>/dev/null)

if [[ -z "$RUNS" ]]; then
    post_error "No completed workflow runs found for current commit"
    exit 1
fi

# Get the most recent run ID
RUN_ID=$(echo "$RUNS" | jq -r '.id' | head -1)

if [[ -z "$RUN_ID" ]]; then
    post_error "Could not find workflow run ID"
    exit 1
fi

# Get jobs for this run
JOBS=$(gh api repos/${GITHUB_REPOSITORY}/actions/runs/${RUN_ID}/jobs --jq '.jobs[]')

# Find matching job
JOB_ID=$(echo "$JOBS" | jq -r --arg name "$JOB_NAME" 'select(.name | contains($name)) | .id' | head -1)

if [[ -z "$JOB_ID" ]]; then
    # List available jobs
    AVAILABLE_JOBS=$(echo "$JOBS" | jq -r '.name' | sort -u | head -10)
    
    RESPONSE="❌ Job not found: \`$JOB_NAME\`

**Available jobs:**"
    
    while IFS= read -r job; do
        RESPONSE="$RESPONSE
• \`$job\`"
    done <<< "$AVAILABLE_JOBS"
    
    post_response "$RESPONSE"
    exit 1
fi

# Get job details
JOB_DETAILS=$(echo "$JOBS" | jq -r --arg id "$JOB_ID" 'select(.id == ($id | tonumber))')
JOB_STATUS=$(echo "$JOB_DETAILS" | jq -r '.conclusion // .status')
JOB_URL=$(echo "$JOB_DETAILS" | jq -r '.html_url')

# Download logs
echo "[$(date)] Downloading logs for job $JOB_ID..."
LOG_FILE="/tmp/ci-logs-${JOB_ID}.txt"

if gh api repos/${GITHUB_REPOSITORY}/actions/jobs/${JOB_ID}/logs > "$LOG_FILE" 2>/dev/null; then
    # Get log size
    LOG_SIZE=$(wc -c < "$LOG_FILE")
    LOG_LINES=$(wc -l < "$LOG_FILE")
    
    # Extract last 50 lines for preview
    LOG_PREVIEW=$(tail -50 "$LOG_FILE")
    
    RESPONSE="## 📄 Logs for Job: $JOB_NAME

**Status**: \`$JOB_STATUS\`
**Size**: $(numfmt --to=iec-i --suffix=B "$LOG_SIZE" 2>/dev/null || echo "$LOG_SIZE bytes")
**Lines**: $LOG_LINES
**Full logs**: [View on GitHub]($JOB_URL)

### Last 50 lines:
\`\`\`
$LOG_PREVIEW
\`\`\`

---
*Full logs are available at the GitHub URL above*"
    
    # Clean up
    rm -f "$LOG_FILE"
else
    RESPONSE="## 📄 Job: $JOB_NAME

**Status**: \`$JOB_STATUS\`
**URL**: $JOB_URL

⚠️ Could not download logs. This may be because:
- The job is still running
- Logs have expired (>90 days)
- Insufficient permissions

Please check the job directly on GitHub."
fi

# Post response
post_response "$RESPONSE"

# Log successful command
log_command "success" "job=$JOB_NAME"