# CI/CD Pipeline Troubleshooting Guide

This guide helps diagnose and resolve common issues with the NeXTRust CI/CD pipeline.

Last updated: 2025-07-18 15:45

## Table of Contents

1. [Common Issues](#common-issues)
2. [AI Service Failures](#ai-service-failures)
3. [Hook System Issues](#hook-system-issues)
4. [Token Tracking Problems](#token-tracking-problems)
5. [Test Failures](#test-failures)
6. [Environment Setup](#environment-setup)

## Common Issues

### Pipeline Status Updates Fail

**Symptoms:**
- Status updates not appearing in logs
- "Failed to acquire lock" errors
- Pipeline appears stuck

**Solutions:**
```bash
# Check for stale lock files
ls -la docs/ci-status/.*.lock

# Remove stale locks (only if certain no other process is running)
rm -f docs/ci-status/.*.lock

# Verify status logging works
python3 ci/scripts/status-append.py test '{"msg":"test"}'
```

### Known Issue Not Recognized

**Symptoms:**
- Same errors keep appearing
- Issues marked as "new" when they're known

**Check:**
```bash
# View known issues
jq . docs/ci-status/known-issues.json

# Test issue matching
echo "error: something failed" | python3 ci/scripts/match-known-issue.py
```

## AI Service Failures

### Gemini CLI Issues

**Rate Limit Errors:**
```bash
# Check current limits
./ci/scripts/analyze-claude-usage.sh help

# Monitor rate limits
tail -f docs/ci-status/metrics/ai-service-*.jsonl | grep gemini
```

**Authentication Failures:**
```bash
# Verify Gemini CLI installation
gemini --version

# Test Gemini CLI directly
echo "test" | gemini -p "respond with ok"
```

### O3 Integration Issues

**Configuration Problems:**
```bash
# Run O3 integration tests
./ci/scripts/test-o3-integration-suite.sh all

# Check specific components
./ci/scripts/test-o3-integration-suite.sh env
./ci/scripts/test-o3-integration-suite.sh api
```

**API Errors:**
```bash
# Test API connectivity
source ~/.zshrc
curl -s -H "Authorization: Bearer $OPENAI_API_KEY" \
  "$O3_ENDPOINT/models" | jq .
```

## Hook System Issues

### Hooks Not Executing

**Check Hook Permissions:**
```bash
# Verify all hooks are executable
find hooks/dispatcher.d -name "*.sh" -type f ! -perm -u+x

# Fix permissions
find hooks/dispatcher.d -name "*.sh" -type f -exec chmod +x {} \;
```

**Debug Hook Execution:**
```bash
# Enable debug mode
export HOOK_DEBUG=1

# Run with verbose output
./hooks/dispatcher.sh pre-tool-use bash "echo test"
```

### Validation Failures

**File Creation Blocked:**
```bash
# Check validation rules
cat hooks/dispatcher.d/pre-tool-use/validate-file-creation.sh

# Test validation
echo "/test.md" | ./ci/scripts/slash/validate-input.sh file
```

## Token Tracking Problems

### ccusage Not Available

**Installation Check:**
```bash
# Run availability check
./ci/scripts/check-ccusage.sh

# Test ccusage functionality
ccusage --help || echo "ccusage not installed"
```

**Manual Token Analysis:**
```bash
# Use external ccusage tool
./ci/scripts/analyze-claude-usage.sh daily

# Export usage data
./ci/scripts/analyze-claude-usage.sh export
```

### Missing Usage Data

**Check Metrics Directory:**
```bash
# Verify metrics directory
ls -la docs/ci-status/metrics/

# Find recent logs
find docs/ci-status/metrics -name "token-usage-*.jsonl" -mtime -1
```

## Test Failures

### Running Specific Test Suites

```bash
# Run all tests (simplified)
./ci/scripts/test-all-simple.sh

# Run O3 integration tests
./ci/scripts/test-o3-integration-suite.sh all

# Run error handling tests
./ci/scripts/test-gemini-error-handling.sh
```

### Python Dependency Issues

If tests fail due to missing Python packages:
```bash
# Use simplified test suite
./ci/scripts/test-all-simple.sh

# Or install dependencies
pip3 install typer rich
```

## Environment Setup

### Essential Environment Variables

```bash
# Check all required variables
env | grep -E "(CLAUDE_|OPENAI_|GEMINI_|O3_)"

# Source environment
source ~/.zshrc

# Verify setup
./ci/scripts/setup-env.sh
```

### Working Directory Issues

```bash
# Ensure working directory is maintained
export CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1

# Check current directory in scripts
pwd
```

## Advanced Debugging

### Enable Verbose Logging

```bash
# Set debug flags
export HOOK_DEBUG=1
export PIPELINE_DEBUG=1
export BASH_XTRACEFD=1

# Run with trace
bash -x ./ci/scripts/request-ai-service.sh --service gemini --type review
```

### Check Failure History

```bash
# View persistent failure database
sqlite3 hooks/dispatcher.d/common/failures.db "SELECT * FROM command_failures ORDER BY timestamp DESC LIMIT 10;"

# Reset failure counts
sqlite3 hooks/dispatcher.d/common/failures.db "DELETE FROM command_failures WHERE command LIKE '%test%';"
```

## Getting Help

If you encounter issues not covered here:

1. Check recent CI runs for patterns
2. Review logs in `docs/ci-status/`
3. Run diagnostic tests: `./ci/scripts/test-all-simple.sh`
4. Check GitHub Actions logs for workflow-specific issues

For persistent issues, consider:
- Clearing all caches and locks
- Reinstalling dependencies
- Checking for recent changes to the pipeline

## Quick Reference

```bash
# Most common fixes
rm -f docs/ci-status/.*.lock              # Clear locks
source ~/.zshrc                           # Reload environment
./ci/scripts/test-all-simple.sh          # Run all tests
./ci/scripts/check-ccusage.sh            # Check token tracking
gemini --version                          # Verify Gemini CLI
```