# Claude Code Deep Integration Features

Last updated: 2025-07-18 08:20

## Overview

This document details the deep integration features implemented for Claude Code 1.0.55+ in the NeXTRust CI/CD pipeline. These features leverage advanced hooks, structured error handling, and unified tooling to create a production-ready development environment.

## Implemented Features

### 1. Git Commit Interceptor (PreToolUse Hook)

**Location**: `hooks/dispatcher.d/pre-tool-use/validate-git-commit.sh`

- Intercepts all git commit commands before execution
- Enforces conventional commit format: `type(scope): description`
- Validates commit message length (10-100 characters)
- Blocks WIP/TODO commits on main/master branches
- Logs commit metadata for analytics

**Supported Types**: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert

### 2. ToolOutput Log Summarization

**Location**: `hooks/dispatcher.d/tool-output/summarize-build-logs.sh`

- Automatically summarizes large command outputs (>10KB)
- Preserves errors, warnings, and key status messages
- Creates artifacts for extremely large outputs (>50KB)
- Reduces token usage while maintaining important information
- Special handling for noisy commands (build, test, install)

### 3. Unified nextrust CLI Tool

**Location**: `ci/scripts/tools/nextrust_cli.py`

- Replaces scattered bash scripts with unified Python CLI
- Commands:
  - `update-status`: Append to pipeline status log
  - `get-phase`: Get current pipeline phase
  - `check-known-issue`: Match errors against known issues
  - `github-comment`: Post GitHub comments with idempotency
  - `rotate-logs`: Archive old logs to prevent bloat

### 4. Structured JSON Error Handling

**Location**: Various scripts (e.g., `build-custom-llvm-v2.sh`)

- All errors emit structured JSON with:
  - error_type
  - error_code
  - message
  - context
  - timestamp
  - suggestions
- Enables deterministic error analysis
- Supports automated error recovery

### 5. Enhanced Prompt Auditing

**Location**: `hooks/dispatcher.d/user-prompt-submit/audit-prompt.sh`

- Captures all user prompts with metadata:
  - Working directory
  - Session ID
  - Command type classification
  - Token estimation
  - Environment info (CI/local)
- Enables usage analytics and debugging

### 6. Success Artifact Generation

**Location**: `hooks/dispatcher.d/post-tool-use/generate-success-artifacts.sh`

- Automatically generates artifacts for successful operations:
  - Build summaries with timing info
  - Test reports with pass/fail counts
  - Draft release notes from commits
- Updates project status boards

### 7. Security Guards

**Location**: `hooks/dispatcher.d/user-prompt-submit/security-guard.sh`

- Blocks destructive commands (rm -rf, fork bombs)
- Prevents system modifications
- Creates audit trail for all prompts
- Configurable forbidden patterns

## Hook Architecture

### Dispatcher Flow

```
UserPromptSubmit → audit-prompt.sh, security-guard.sh
     ↓
PreToolUse → validate-git-commit.sh, validate-cwd.sh
     ↓
Tool Execution
     ↓
ToolOutput → summarize-build-logs.sh
     ↓
PostToolUse → generate-success-artifacts.sh
     ↓
Stop → (cleanup if needed)
```

### Configuration

All hooks are managed through the modular dispatcher (`hooks/dispatcher-v2.sh`) which:
- Routes events to appropriate hook scripts
- Handles errors gracefully
- Supports enable/disable via configuration
- Provides consistent logging

## Testing

The `ci/scripts/test-deep-integration.sh` script validates all features:

1. Git commit validation (conventional format)
2. ToolOutput summarization (large outputs)
3. nextrust CLI functionality
4. Structured error JSON format
5. Enhanced prompt auditing
6. Success artifact generation
7. Dispatcher routing

## Best Practices

1. **Error Handling**: Always use structured JSON errors
2. **Token Management**: Summarize large outputs to reduce costs
3. **Auditing**: All significant actions should be logged
4. **Testing**: Run integration tests after hook changes
5. **Mocking**: Use mocks for external dependencies in tests

## Future Enhancements

1. **Custom Tools**: Create MCP-compatible tools for specialized tasks
2. **ML-based Error Analysis**: Use patterns to predict failures
3. **Automated Recovery**: Implement self-healing for common issues
4. **Performance Monitoring**: Track command execution times
5. **Cost Optimization**: More aggressive token reduction strategies

## Troubleshooting

### Common Issues

1. **Python dependencies**: Install with `pip3 install typer click`
2. **Hook permissions**: Ensure all hooks are executable
3. **Path issues**: Hooks assume relative paths from repo root
4. **JSON parsing**: Use `jq` for all JSON operations

### Debug Mode

Enable debug output:
```bash
export CLAUDE_CODE_DEBUG=1
```

### Logs

- Prompt audit: `docs/prompts/audit-YYYYMMDD.jsonl`
- Pipeline status: `docs/ci-status/pipeline-log.json`
- Build artifacts: `docs/ci-status/build-logs/`

## Integration with CI/CD

These features integrate seamlessly with:
- GitHub Actions workflows
- Gemini code reviews (`GEMINI.md`)
- Phase-based pipeline execution
- Known issue detection
- Status rotation and archival

The deep integration transforms Claude Code from a coding assistant into a full development environment participant, with awareness of project conventions, error patterns, and workflow requirements.