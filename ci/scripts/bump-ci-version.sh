#!/usr/bin/env bash
# ci/scripts/bump-ci-version.sh - Bump CI configuration version
#
# Purpose: Update CI_CONFIG_VERSION to enable new features
# Usage: ./ci/scripts/bump-ci-version.sh
#
set -uo pipefail

CONFIG_FILE=".github/workflows/nextrust-ci.yml"
OLD_VERSION="2.0"
NEW_VERSION="2.1"

echo "=== Bumping CI Configuration Version ==="
echo

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Check current version
if grep -q "CI_CONFIG_VERSION: $OLD_VERSION" "$CONFIG_FILE"; then
    echo "Current version: $OLD_VERSION"
    echo "New version: $NEW_VERSION"
    echo
    
    # Update version
    sed -i.bak "s/CI_CONFIG_VERSION: $OLD_VERSION/CI_CONFIG_VERSION: $NEW_VERSION/" "$CONFIG_FILE"
    
    echo "✅ Updated CI_CONFIG_VERSION to $NEW_VERSION"
    echo
    echo "New features enabled:"
    echo "- UserPromptSubmit hook for security and audit"
    echo "- CWD validation with \$CCODE_CWD"
    echo "- Argument hints for slash commands"
    echo "- Shell snapshots on file errors"
    echo
    echo "⚠️  Remember to commit this change!"
else
    echo "CI_CONFIG_VERSION is not currently $OLD_VERSION"
    grep "CI_CONFIG_VERSION:" "$CONFIG_FILE" || echo "No CI_CONFIG_VERSION found"
fi