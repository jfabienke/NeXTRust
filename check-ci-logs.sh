#!/bin/bash
# Quick script to check CI failure logs

RUN_ID="${1:-$(gh run list --limit 1 --json databaseId | jq -r '.[0].databaseId')}"

echo "Checking CI run $RUN_ID..."
echo

# Get a failed job
FAILED_JOB=$(gh api repos/jfabienke/NeXTRust/actions/runs/$RUN_ID/jobs | jq -r '.jobs[] | select(.conclusion == "failure") | .id' | head -1)

if [[ -z "$FAILED_JOB" ]]; then
    echo "No failed jobs found"
    exit 0
fi

echo "Checking failed job $FAILED_JOB logs..."
echo

# Download logs
gh api repos/jfabienke/NeXTRust/actions/jobs/$FAILED_JOB/logs --header 'Accept: application/vnd.github.v3.raw' > /tmp/ci-logs.txt 2>/dev/null

# Find error
echo "=== LLVM Build Errors ==="
grep -A 10 -B 5 "error:" /tmp/ci-logs.txt | tail -100

echo
echo "=== Hook Triggers ==="
grep -E "trigger-hook|Hook dispatcher" /tmp/ci-logs.txt | tail -20