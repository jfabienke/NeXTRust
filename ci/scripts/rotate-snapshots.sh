#!/usr/bin/env bash
# ci/scripts/rotate-snapshots.sh - Rotate shell snapshots
#
# Purpose: Clean up old shell snapshots following 30-day retention policy
# Usage: Called by maintenance workflow or manually
#
set -uo pipefail

SNAPSHOT_DIR="docs/ci-status/snapshots"
RETENTION_DAYS=30

echo "[$(date)] Starting shell snapshot rotation..."

if [[ ! -d "$SNAPSHOT_DIR" ]]; then
    echo "No snapshot directory found, nothing to rotate"
    exit 0
fi

# Count current snapshots
TOTAL_SNAPSHOTS=$(find "$SNAPSHOT_DIR" -name "*.gz" -type f | wc -l)
echo "Found $TOTAL_SNAPSHOTS total snapshots"

# Find and remove old snapshots
OLD_SNAPSHOTS=$(find "$SNAPSHOT_DIR" -name "*.gz" -type f -mtime +$RETENTION_DAYS)
OLD_COUNT=$(echo "$OLD_SNAPSHOTS" | grep -c . || echo 0)

if [[ $OLD_COUNT -gt 0 ]]; then
    echo "Removing $OLD_COUNT snapshots older than $RETENTION_DAYS days:"
    
    while IFS= read -r snapshot; do
        if [[ -n "$snapshot" ]]; then
            echo "  - $(basename "$snapshot")"
            rm -f "$snapshot"
        fi
    done <<< "$OLD_SNAPSHOTS"
    
    # Log rotation
    python3 ci/scripts/status-append.py "maintenance" \
        "{\"action\": \"snapshot_rotation\", \"removed\": $OLD_COUNT, \"retention_days\": $RETENTION_DAYS}"
else
    echo "No snapshots older than $RETENTION_DAYS days found"
fi

# Clean up snapshot markers
if [[ -d ".claude/snapshots" ]]; then
    find .claude/snapshots -name ".captured-*" -type f -mtime +1 -delete
fi

echo "[$(date)] Snapshot rotation complete"