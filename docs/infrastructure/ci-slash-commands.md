# NeXTRust CI Slash Commands

*Last updated: 2025-07-18 17:00*

## Overview

The NeXTRust CI pipeline supports slash commands in Pull Request comments, allowing developers to interact with the CI system without leaving GitHub. This provides a human-in-the-loop control surface for the agent-driven pipeline.

## Quick Start

To use a slash command, simply comment on a Pull Request:

```
/ci-help
```

The CI bot will respond with available commands and their usage.

## Available Commands

### Query Commands (Read-Only)

#### `/ci-help`
Show all available slash commands with usage examples.

**Example:**
```
/ci-help
```

#### `/ci-status`
Display the current pipeline status from `pipeline-log.md`.

**Example:**
```
/ci-status
```

#### `/ci-check-phase`
Show detailed information about the current phase including progress and deliverables.

**Example:**
```
/ci-check-phase
```

#### `/ci-get-logs <job-name>`
Retrieve logs for a specific CI job. The job name can be partial but should be unique enough to identify the job.

**Example:**
```
/ci-get-logs build-matrix-ubuntu-latest-release-m68040
```

### Action Commands (Write Permission)

#### `/ci-retry-job <job-name>`
Re-run a specific failed job from the workflow. Only works for jobs that have already failed.

**Example:**
```
/ci-retry-job build-matrix-macos-latest-debug-m68030
```

#### `/ci-reset-phase <phase-id>`
Reset a phase to allow it to run again. Useful when a phase is stuck or needs to be re-executed.

**Example:**
```
/ci-reset-phase phase-3
```

**Available phases:**
- `phase-1` - Environment Setup
- `phase-2` - LLVM Backend Modifications
- `phase-3` - Rust Target Implementation
- `phase-4` - Emulation Testing
- `phase-5` - Standard Library Port

#### `/ci-clear-backoff`
Clear the failure backoff counter for the current commit. Use this when a commit has hit the 3-failure limit.

**Example:**
```
/ci-clear-backoff
```

#### `/ci-force-review <channel>`
Trigger an immediate AI review without waiting for phase completion.

**Example:**
```
/ci-force-review o3      # Request design review from OpenAI o3
/ci-force-review gemini  # Request implementation review from Google Gemini
```

### Admin Commands

#### `/ci-clear-cache`
Clear the GitHub Actions cache for the current branch. This forces a fresh build without cached dependencies.

**Example:**
```
/ci-clear-cache
```

## Security & Permissions

### User Authorization
- Only repository members, owners, and collaborators can use slash commands
- Commands are validated at the GitHub Actions workflow level
- Each command execution is logged with user attribution

### Argument Validation
**IMPORTANT**: All command arguments are strictly validated to prevent injection attacks:
- Arguments must match pattern: `[a-zA-Z0-9_-]+`
- All variables are properly quoted in shell scripts
- Commands accept at most one argument

### Rate Limiting
- 30-second cooldown per user between commands
- Prevents command spam and resource abuse
- Rate limit status is shown if triggered

### Audit Logging
All commands are logged to:
- `docs/ci-status/command-log.json` - Command audit trail
- Pipeline status system via `status-append.py`
- GitHub Actions logs for debugging

## Architecture

### Event Flow
1. User posts a comment with `/ci-...` command
2. `ci-slash-commands.yml` workflow triggers on `issue_comment`
3. Workflow validates user permissions and parses command
4. Main CI pipeline is triggered via `workflow_dispatch`
5. Dispatcher detects `CI_COMMAND` and routes to appropriate script
6. Command script executes and posts response back to PR

### File Structure
```
ci/scripts/slash/
├── common.sh           # Shared utilities and security functions
├── ci-help.sh         # Help command
├── ci-status.sh       # Status query
├── ci-check-phase.sh  # Phase details
├── ci-get-logs.sh     # Log retrieval
├── ci-retry-job.sh    # Job retry
├── ci-reset-phase.sh  # Phase reset
├── ci-clear-backoff.sh # Clear failure counter
├── ci-force-review.sh # Trigger AI review
└── ci-clear-cache.sh  # Clear caches
```

## Success Metrics

The system tracks:
- **Adoption**: Unique users per week
- **Efficiency**: Time saved by `/ci-retry-job`
- **Reliability**: Command success rate
- **Usage**: Most used commands

View metrics in the [CI Slash Commands Dashboard](../../monitoring/dashboards/ci-slash-metrics.json).

## Troubleshooting

### Command Not Found
```
❌ Unknown command: `/ci-build`. Try `/ci-help` for available commands.
```
**Solution**: Check command spelling or use `/ci-help` to see valid commands.

### Rate Limited
```
❌ Error: Rate limit: please wait 15 seconds before next command
```
**Solution**: Wait for the cooldown period before trying again.

### Permission Denied
```
❌ Error: Failed to retry job. Please check if you have permission to re-run workflows.
```
**Solution**: Ensure you have write access to the repository.

### Job Not Found
```
❌ Job not found: `build-ubuntu`

Available jobs:
• build-matrix-ubuntu-latest-debug-m68030
• build-matrix-ubuntu-latest-debug-m68040
```
**Solution**: Use the exact job name from the list.

## Development

### Adding New Commands

1. Create a new script in `ci/scripts/slash/`:
```bash
#!/usr/bin/env bash
source ci/scripts/slash/common.sh

# Your command logic here
post_success "Command executed successfully"
log_command "success"
```

2. Make it executable:
```bash
chmod +x ci/scripts/slash/ci-your-command.sh
```

3. Update `/ci-help` command to include the new command.

4. The dispatcher will automatically discover and route to your command.

### Testing Commands Locally

```bash
# Set test environment
export CI_COMMAND="ci-status"
export CI_PR_NUMBER="123"
export GITHUB_REPOSITORY="owner/repo"
export CI_TRIGGERED_BY="testuser"

# Run dispatcher
./hooks/dispatcher-v2.sh slash-command
```

## Best Practices

1. **Use `/ci-help` first** when unsure about available commands
2. **Check `/ci-status` before retrying** to understand current state
3. **Clear backoff before pushing fixes** if commit has failed multiple times
4. **Be specific with job names** when using `/ci-retry-job`
5. **Wait for cooldown** instead of spamming commands

## Security Guidelines

For maintainers adding new commands:

1. **Always validate arguments**: Use `validate_arg` function
2. **Quote all variables**: `"$var"` not `$var`
3. **Use locks for mutations**: Call `acquire_command_lock`
4. **Check permissions**: Use `check_write_permission` for destructive operations
5. **Log all actions**: Call `log_command` with status

## Future Enhancements

- GitHub reactions as quick actions (e.g., 🚀 to retry)
- Command aliases for common operations
- Batch operations (retry all failed jobs)
- Command history in PR timeline
- Integration with external monitoring

---

*For implementation details, see [ci-v2-implementation-plan.md](ci-v2-implementation-plan.md)*