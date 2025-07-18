#!/usr/bin/env bash
# ---
# argument-hint: "<job-name>"
# ---
# ci/scripts/slash/ci-retry-job.sh - Retry a failed job
#
# Purpose: Re-run a specific failed job from the workflow
# Usage: /ci-retry-job <job-name>
# Security: Validates job name pattern, uses proper quoting

source ci/scripts/slash/common.sh

# SECURITY: Validate argument using type-specific validation
JOB_NAME=$(validate_arg "${CI_ARGS:-}" 'job_name' 'job name')

# Acquire lock for mutation
acquire_command_lock

# Get current workflow run for this commit
echo "[$(date)] Finding workflow run for commit ${GITHUB_SHA}..."

RUNS=$(gh api repos/${GITHUB_REPOSITORY}/actions/runs \
    --jq '.workflow_runs[] | select(.head_sha == env.GITHUB_SHA)' \
    -f per_page=10 2>/dev/null)

if [[ -z "$RUNS" ]]; then
    post_error "No workflow runs found for current commit"
    exit 1
fi

# Get the most recent run
RUN_ID=$(echo "$RUNS" | jq -r '.id' | head -1)
RUN_STATUS=$(echo "$RUNS" | jq -r '.status' | head -1)

if [[ -z "$RUN_ID" ]]; then
    post_error "Could not find workflow run ID"
    exit 1
fi

echo "[$(date)] Found run ID: $RUN_ID (status: $RUN_STATUS)"

# Get jobs for this run
JOBS=$(gh api repos/${GITHUB_REPOSITORY}/actions/runs/"$RUN_ID"/jobs --jq '.jobs[]' 2>/dev/null)

if [[ -z "$JOBS" ]]; then
    post_error "Could not retrieve jobs for run $RUN_ID"
    exit 1
fi

# Find the specific job (exact match first, then partial match)
JOB_DATA=$(echo "$JOBS" | jq -r --arg name "$JOB_NAME" 'select(.name == $name)' | head -1)

if [[ -z "$JOB_DATA" ]]; then
    # Try partial match
    JOB_DATA=$(echo "$JOBS" | jq -r --arg name "$JOB_NAME" 'select(.name | contains($name))' | head -1)
fi

if [[ -z "$JOB_DATA" ]]; then
    # List available jobs for help
    AVAILABLE_JOBS=$(echo "$JOBS" | jq -r '.name' | sort -u | head -10)
    
    RESPONSE="❌ Job not found: \`$JOB_NAME\`

**Available jobs in run #$RUN_ID:**"
    
    while IFS= read -r job; do
        RESPONSE="$RESPONSE
• \`$job\`"
    done <<< "$AVAILABLE_JOBS"
    
    RESPONSE="$RESPONSE

*Tip: Use the exact job name from the list above*"
    
    post_response "$RESPONSE"
    log_command "failed" "job_not_found"
    exit 1
fi

# Extract job details
JOB_ID=$(echo "$JOB_DATA" | jq -r '.id')
JOB_FULL_NAME=$(echo "$JOB_DATA" | jq -r '.name')
JOB_STATUS=$(echo "$JOB_DATA" | jq -r '.conclusion // .status')

echo "[$(date)] Found job: $JOB_FULL_NAME (ID: $JOB_ID, status: $JOB_STATUS)"

# Check if job can be retried
if [[ "$JOB_STATUS" == "success" ]]; then
    post_error "Job \`$JOB_FULL_NAME\` already succeeded. Only failed jobs can be retried."
    log_command "failed" "job_already_success"
    exit 1
fi

if [[ "$JOB_STATUS" == "in_progress" || "$JOB_STATUS" == "queued" ]]; then
    post_error "Job \`$JOB_FULL_NAME\` is still running (status: $JOB_STATUS)"
    log_command "failed" "job_still_running"
    exit 1
fi

# SECURITY: Always quote variables in commands
echo "[$(date)] Attempting to re-run job $JOB_ID..."

if gh run rerun --job "$JOB_ID" "$RUN_ID" 2>/dev/null; then
    RESPONSE="✅ Successfully triggered retry for job: \`$JOB_FULL_NAME\`

**Run ID**: #$RUN_ID
**Job ID**: $JOB_ID
**Previous status**: $JOB_STATUS

The job should start running shortly. Check the [Actions tab](${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${RUN_ID}) for progress."
    
    post_success "$RESPONSE"
    log_command "success" "job=$JOB_FULL_NAME,run=$RUN_ID"
else
    # Try alternative retry method for failed jobs only
    if [[ "$JOB_STATUS" == "failure" ]] && gh run rerun --failed "$RUN_ID" 2>/dev/null; then
        post_success "Retried all failed jobs in run #$RUN_ID (including \`$JOB_FULL_NAME\`)"
        log_command "success" "all_failed_jobs,run=$RUN_ID"
    else
        post_error "Failed to retry job. Please check if you have permission to re-run workflows."
        log_command "failed" "permission_denied"
        exit 1
    fi
fi