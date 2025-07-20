#!/usr/bin/env bash
# ---
# argument-hint: ""
# ---
# ci/scripts/slash/ci-help.sh - Show available slash commands
#
# Purpose: Display help for all available CI slash commands
# Usage: /ci-help

source ci/scripts/slash/common.sh

# Build help text
HELP_TEXT=$(cat << 'EOF'
## 🤖 NeXTRust CI Slash Commands

**Query Commands** (read-only):
• `/ci-help` - Show this help message
• `/ci-status` - Display current pipeline status
• `/ci-check-phase` - Show current phase details and progress
• `/ci-get-logs <job>` - Download logs for specific matrix job

**Action Commands** (require write permission):
• `/ci-retry-job <job>` - Retry a failed matrix job
• `/ci-reset-phase <phase>` - Reset phase for retry
• `/ci-clear-backoff` - Clear failure backoff counter for current commit
• `/ci-force-review <o3|gemini>` - Trigger immediate AI review

**AI Assistant Commands**:
• `/ci-ai-review [--service gemini|o3] [files...]` - Request AI code review
• `/ci-design-help [--prompt "question"]` - Get O3 design guidance

**Admin Commands**:
• `/ci-clear-cache` - Clear GitHub Actions cache for current branch

### Usage Examples:
```
/ci-status
/ci-retry-job build-matrix-ubuntu-latest-release-m68040
/ci-reset-phase phase-3
/ci-force-review gemini
/ci-ai-review --service gemini src/*.rs
/ci-design-help --prompt "Best approach for M68k atomics?"
```

### Notes:
- All commands are rate-limited (30s cooldown per user)
- Commands are logged for audit purposes
- Arguments must match pattern: `[a-zA-Z0-9_-]+`
- For issues, check logs with `/ci-get-logs`

### Additional Resources:
- 📖 [Review Guidelines](GEMINI.md) - AI reviewer checklist and standards
- 📚 [CI Documentation](docs/infrastructure/ci-pipeline.md) - Full pipeline guide
- 🔧 [Troubleshooting](docs/infrastructure/ci-pipeline.md#troubleshooting)

EOF
)

# Post help message
post_response "$HELP_TEXT"

# Log successful command
log_command "success"