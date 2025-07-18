# Claude Code CI Setup Guide

*Last updated: 2025-07-18 19:30*

## Overview

This guide explains how to configure Claude Code as the primary AI agent in the NeXTRust CI pipeline.

## Required GitHub Secrets

You must add the following secret to your GitHub repository:

1. **ANTHROPIC_API_KEY** - Your Anthropic API key for Claude Code
   - Get it from: https://console.anthropic.com/account/keys
   - Add via: Settings → Secrets and variables → Actions → New repository secret
   - Name: `ANTHROPIC_API_KEY`
   - Value: Your API key (starts with `sk-ant-api03-`)

## How It Works

1. **CI triggers** on push/PR
2. **Claude Code CLI** is installed via npm
3. **Agent feedback loop** runs with phase-specific tasks
4. **Hooks fire** during tool execution:
   - PreToolUse: Validates actions
   - PostToolUse: Handles failures
   - Stop: Triggers reviews
5. **AI escalation** when needed:
   - Design issues → OpenAI o3
   - Code reviews → Gemini 2.5 Pro

## Testing the Setup

After adding the secret and pushing changes:

1. Check the Actions tab for the running workflow
2. Look for "Run Agent Feedback Loop" step
3. Verify hooks are being triggered in logs
4. Check `.claude/hook-logs/` in artifacts

## Troubleshooting

### Claude Code not found
- Ensure Node.js 20+ is installed
- Check npm install succeeded
- Verify ANTHROPIC_API_KEY is set

### Hooks not firing
- Check `chmod +x hooks/dispatcher.sh`
- Verify `.claude/settings.json` exists
- Look for hook logs in CI artifacts

### Build failures
- Check hook logs for error analysis
- Look for escalation to o3/Gemini
- Review status artifacts in `docs/ci-status/`

## Local Testing

To test the agent loop locally:
```bash
export ANTHROPIC_API_KEY="your-key"
./ci/scripts/agent-feedback-loop.sh
```

This will run Claude Code with the same configuration as CI.