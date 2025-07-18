#!/usr/bin/env bash
# ci/scripts/setup-env.sh - Centralized environment setup for CI
#
# Purpose: Export all required environment variables for CI pipeline
# Usage: Called as first step in every GitHub Actions job

set -euo pipefail

echo "::group::Environment Setup"

# Matrix variables (with defaults for local testing)
if [[ -n "${GITHUB_ENV:-}" ]]; then
    # GitHub Actions environment
    echo "CPU_VARIANT=${CPU_VARIANT:-default}" >> "$GITHUB_ENV"
    echo "OS_NAME=${OS_NAME:-$(uname -s)}" >> "$GITHUB_ENV"
    echo "RUST_PROFILE=${RUST_PROFILE:-debug}" >> "$GITHUB_ENV"
    
    # CI context
    echo "COMMIT_SHA=${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo "no-commit")}" >> "$GITHUB_ENV"
    echo "RUN_ID=${GITHUB_RUN_ID:-local-$(date +%s)}" >> "$GITHUB_ENV"
    echo "RUN_ATTEMPT=${GITHUB_RUN_ATTEMPT:-1}" >> "$GITHUB_ENV"
    echo "RUNNER_NAME=${RUNNER_NAME:-$RUNNER_NAME}" >> "$GITHUB_ENV"
    
    # Feature flags
    echo "NEXTRUST_DEBUG=${NEXTRUST_DEBUG:-0}" >> "$GITHUB_ENV"
    echo "SKIP_EXTERNAL_APIS=${SKIP_EXTERNAL_APIS:-0}" >> "$GITHUB_ENV"
    echo "DRY_RUN=${DRY_RUN:-0}" >> "$GITHUB_ENV"
    
    # Claude Code working directory management
    echo "CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1" >> "$GITHUB_ENV"
    
    # Slash command context (if present)
    if [[ -n "${CI_COMMAND:-}" ]]; then
        echo "CI_COMMAND=${CI_COMMAND}" >> "$GITHUB_ENV"
        echo "CI_ARGS=${CI_ARGS:-}" >> "$GITHUB_ENV"
        echo "CI_PR_NUMBER=${CI_PR_NUMBER:-}" >> "$GITHUB_ENV"
        echo "CI_TRIGGERED_BY=${CI_TRIGGERED_BY:-}" >> "$GITHUB_ENV"
    fi
else
    # Local environment - export directly
    export CPU_VARIANT="${CPU_VARIANT:-default}"
    export OS_NAME="${OS_NAME:-$(uname -s)}"
    export RUST_PROFILE="${RUST_PROFILE:-debug}"
    export COMMIT_SHA="${COMMIT_SHA:-$(git rev-parse HEAD 2>/dev/null || echo "no-commit")}"
    export RUN_ID="${RUN_ID:-local-$(date +%s)}"
    export RUN_ATTEMPT="${RUN_ATTEMPT:-1}"
    export RUNNER_NAME="${RUNNER_NAME:-local}"
    export NEXTRUST_DEBUG="${NEXTRUST_DEBUG:-0}"
    export SKIP_EXTERNAL_APIS="${SKIP_EXTERNAL_APIS:-0}"
    export DRY_RUN="${DRY_RUN:-0}"
    
    # Claude Code working directory management
    export CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1
    
    # Slash command context (if present)
    if [[ -n "${CI_COMMAND:-}" ]]; then
        export CI_COMMAND="${CI_COMMAND}"
        export CI_ARGS="${CI_ARGS:-}"
        export CI_PR_NUMBER="${CI_PR_NUMBER:-}"
        export CI_TRIGGERED_BY="${CI_TRIGGERED_BY:-}"
    fi
fi

# Display current environment
echo "Environment variables set:"
echo "  CPU_VARIANT=${CPU_VARIANT:-not set}"
echo "  OS_NAME=${OS_NAME:-not set}"
echo "  RUST_PROFILE=${RUST_PROFILE:-not set}"
echo "  COMMIT_SHA=${COMMIT_SHA:-not set}"
echo "  RUN_ID=${RUN_ID:-not set}"
echo "  RUN_ATTEMPT=${RUN_ATTEMPT:-not set}"
echo "  RUNNER_NAME=${RUNNER_NAME:-not set}"

echo "::endgroup::"