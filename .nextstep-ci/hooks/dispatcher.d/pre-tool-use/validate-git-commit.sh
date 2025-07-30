#!/bin/bash
# hooks/dispatcher.d/pre-tool-use/validate-git-commit.sh
#
# Purpose: Intercept and validate git commit messages
# Ensures commits follow conventional format and project standards
#
set -uo pipefail

# Extract tool name and command
TOOL_NAME=$(echo "$PAYLOAD" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
COMMAND=$(echo "$PAYLOAD" | jq -r '.tool_args.command // ""' 2>/dev/null || echo "")

# Only process git commit commands
if [[ "$TOOL_NAME" != "Bash" ]] || [[ ! "$COMMAND" =~ ^git[[:space:]]+commit ]]; then
    exit 0
fi

echo "[$(date)] Intercepting git commit for validation..."

# Extract commit message from the command
# Handle various formats: git commit -m "msg", git commit --message="msg", etc.
COMMIT_MSG=""
if [[ "$COMMAND" =~ -m[[:space:]]+\"([^\"]+)\" ]]; then
    COMMIT_MSG="${BASH_REMATCH[1]}"
elif [[ "$COMMAND" =~ --message=\"([^\"]+)\" ]]; then
    COMMIT_MSG="${BASH_REMATCH[1]}"
elif [[ "$COMMAND" =~ -m[[:space:]]+\'([^\']+)\' ]]; then
    COMMIT_MSG="${BASH_REMATCH[1]}"
fi

if [[ -z "$COMMIT_MSG" ]]; then
    echo "[$(date)] No commit message found in command, allowing interactive commit"
    exit 0
fi

# Validate conventional commit format
CONVENTIONAL_PATTERN="^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?: .{1,100}$"
if ! [[ "$COMMIT_MSG" =~ $CONVENTIONAL_PATTERN ]]; then
    echo "::error::Commit message does not follow conventional format"
    echo "::error::Expected: <type>[(scope)]: <description>"
    echo "::error::Types: feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"
    echo "::error::Example: feat(llvm): add support for m68k relocations"
    echo "::error::Your message: $COMMIT_MSG"
    
    # Log rejection
    if command -v python3 &>/dev/null && [[ -x "ci/scripts/status-append.py" || -x "$(which status-append.py 2>/dev/null)" ]]; then
        python3 ci/scripts/status-append.py "commit_rejected" \
            "{\"message\": \"$(echo "$COMMIT_MSG" | jq -Rs .)\", \"reason\": \"format_violation\"}" 2>/dev/null || true
    fi
    
    exit 1
fi

# Additional validations
# 1. Check message length (should be 50-100 chars for summary)
MSG_LENGTH=${#COMMIT_MSG}
if [[ $MSG_LENGTH -lt 10 ]]; then
    echo "::error::Commit message too short (minimum 10 characters)"
    exit 1
elif [[ $MSG_LENGTH -gt 100 ]]; then
    echo "::warning::Commit message summary should be under 100 characters (currently $MSG_LENGTH)"
fi

# 2. Check for WIP commits in production branches
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
    if [[ "$COMMIT_MSG" =~ (WIP|wip|TODO|FIXME) ]]; then
        echo "::error::WIP/TODO commits not allowed on $CURRENT_BRANCH branch"
        exit 1
    fi
fi

# 3. Extract type and scope for metrics
if [[ "$COMMIT_MSG" =~ ^([a-z]+) ]]; then
    COMMIT_TYPE="${BASH_REMATCH[1]}"
    # Extract scope if present
    if [[ "$COMMIT_MSG" =~ ^[a-z]+\(([^\)]+)\) ]]; then
        COMMIT_SCOPE="${BASH_REMATCH[1]}"
    else
        COMMIT_SCOPE="none"
    fi
    
    # Log successful validation with metadata
    if command -v python3 &>/dev/null && [[ -x "ci/scripts/status-append.py" || -x "$(which status-append.py 2>/dev/null)" ]]; then
        python3 ci/scripts/status-append.py "commit_validated" \
            "{\"type\": \"$COMMIT_TYPE\", \"scope\": \"$COMMIT_SCOPE\", \"length\": $MSG_LENGTH, \"branch\": \"$CURRENT_BRANCH\"}" 2>/dev/null || true
    fi
fi

echo "[$(date)] ✅ Commit message validated: $COMMIT_MSG"

# Optional: Enhance commit message with metadata
# This could add issue numbers, co-authors, etc.
if [[ -n "${ENHANCE_COMMITS:-}" ]] && [[ "$ENHANCE_COMMITS" == "true" ]]; then
    echo "[$(date)] Enhancing commit message with metadata..."
    # Future enhancement point
fi