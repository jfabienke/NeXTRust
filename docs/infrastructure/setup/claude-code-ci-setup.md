# Claude Code Hooks in CI

*Last updated: 2025-07-18 20:00*

## Overview

The NeXTRust CI pipeline uses Claude Code's hook system to provide intelligent build orchestration. Since Claude Code CLI requires browser authentication (not available in CI), the hooks are triggered directly by the build scripts.

## How It Works

### In CI (GitHub Actions)

1. **Build scripts** run directly (no Claude Code CLI)
2. **Scripts trigger hooks** via `trigger-hook.sh`:
   - PreToolUse: Before build commands
   - PostToolUse: After completion (success or failure)
3. **Hook dispatcher** processes events:
   - Validates phase alignment
   - Analyzes failures
   - Updates status artifacts
4. **AI escalation** when needed:
   - Design issues → OpenAI o3
   - Code reviews → Gemini 2.5 Pro

### Locally (with Claude Code)

When you run Claude Code locally, the hooks trigger automatically through `.claude/settings.json` configuration.

## Hook Triggering in CI

The build scripts now include hook triggers:

```bash
# Pre-hook before build
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    ./ci/scripts/trigger-hook.sh pre Bash "$0 $*" || true
fi

# ... build logic ...

# Post-hook after completion
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    ./ci/scripts/trigger-hook.sh post Bash "$0 $*" $EXIT_CODE || true
fi
```

## Required GitHub Secrets

The following secrets enable AI escalation:

1. **O3_ENDPOINT** - OpenAI o3 endpoint (optional)
2. **OPENAI_API_KEY** - For o3 design decisions (optional)
3. **GEMINI_API_KEY** - For Gemini code reviews (optional)

These are optional - the pipeline works without them but won't have AI escalation capabilities.

## Testing Hook Triggers

After pushing changes:

1. Check the Actions tab for the running workflow
2. Look for hook trigger messages in build logs
3. Check artifacts for `.claude/hook-logs/`
4. Verify status updates in `docs/ci-status/`

## Troubleshooting

### Hooks not firing in CI
- Check `trigger-hook.sh` is executable
- Verify `GITHUB_ACTIONS` environment variable is set
- Look for "dispatcher started" in logs

### Hooks not firing locally
- Ensure Claude Code is running (not just the CLI)
- Check `.claude/settings.json` exists
- Verify hook scripts are executable

### Build failures
- Check `.claude/hook-logs/` for error analysis
- Review `docs/ci-status/pipeline-log.json`
- Look for failure patterns in hook logs

## Local Development

When running locally with Claude Code:
```bash
# Claude Code will trigger hooks automatically
ci/scripts/build-custom-llvm.sh
```

The hooks provide the same intelligent assistance locally as in CI.