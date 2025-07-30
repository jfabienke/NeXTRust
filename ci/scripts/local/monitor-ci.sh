#!/bin/bash
# Quick CI monitoring script

echo "=== NeXTRust CI Monitor ==="
echo "Press Ctrl+C to stop"
echo

while true; do
    clear
    echo "=== NeXTRust CI Status ==="
    echo "Time: $(date)"
    echo
    
    # Get latest run
    RUN_INFO=$(gh run list --limit 1 --json status,name,headBranch,databaseId,conclusion,startedAt 2>/dev/null)
    if [[ $? -eq 0 ]] && [[ -n "$RUN_INFO" ]]; then
        STATUS=$(echo "$RUN_INFO" | jq -r '.[0].status')
        NAME=$(echo "$RUN_INFO" | jq -r '.[0].name')
        BRANCH=$(echo "$RUN_INFO" | jq -r '.[0].headBranch')
        RUN_ID=$(echo "$RUN_INFO" | jq -r '.[0].databaseId')
        STARTED=$(echo "$RUN_INFO" | jq -r '.[0].startedAt')
        
        # Calculate duration
        if [[ "$STARTED" != "null" ]]; then
            START_EPOCH=$(date -d "$STARTED" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$STARTED" +%s 2>/dev/null)
            NOW_EPOCH=$(date +%s)
            DURATION=$((NOW_EPOCH - START_EPOCH))
            DURATION_MIN=$((DURATION / 60))
            DURATION_SEC=$((DURATION % 60))
            DURATION_STR="${DURATION_MIN}m ${DURATION_SEC}s"
        else
            DURATION_STR="Not started"
        fi
        
        echo "Latest Run: $NAME"
        echo "Branch: $BRANCH"
        echo "Status: $STATUS"
        echo "Duration: $DURATION_STR"
        echo "Run ID: $RUN_ID"
        echo
        
        if [[ "$STATUS" == "in_progress" ]]; then
            echo "=== Job Status ==="
            gh run view "$RUN_ID" --json jobs | jq -r '.jobs[] | 
                select(.status != "completed") | 
                "\(.name): \(.status) [\(.conclusion // "running")]"' | head -10
            
            echo
            echo "=== Recent Steps ==="
            # Try to get some log output (this might not work while running)
            gh run view "$RUN_ID" --log 2>/dev/null | tail -20 | grep -E "Building|Compiling|Success|Error|Failed" || echo "Logs not yet available..."
        fi
    else
        echo "No CI runs found or GitHub CLI error"
    fi
    
    echo
    echo "Refreshing in 30 seconds..."
    sleep 30
done