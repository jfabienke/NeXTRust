# Claude Code 1.0.54 – Project-Specific Usage Notes

Purpose: Tell Claude Code exactly how NeXTRust leverages the new 1.0.54 capabilities (except the Windows-specific OAuth fix). These notes are automatically loaded via `include:docs/ai/claude-code-1.0.54-guidelines.md` at runtime.

---

## 1. New Hook: UserPromptSubmit

### What fires
- Runs immediately after a developer presses `⇧ ⏎` in the Claude interactive shell.
- Provides the submitted text in `hook.prompt` and the current working directory in `hook.cwd`.

### How to respond (NeXTRust rules)

1. **Guard-rail** — reject prompts that contain destructive patterns:

```yaml
forbidden:
  - 'rm -rf'
  - ':(){:|:&};:'   # fork-bomb
```

If a match occurs, output `::error::Destructive command blocked` and `exit 1`.

2. **Phase banner** — prepend a one-line banner to the prompt:

```
[Phase $PHASE_ID • $PROJECT_SHA] >
```

3. **Audit** — append JSON record `{timestamp,prompt,phase}` to `docs/ci-status/prompt-log.json` via `status-append.py`.

---

## 2. CWD in Hook Inputs

- All `PreToolUse` validators now read `$CCODE_CWD`.
- Policy:
  - Phase 3 ➜ CWD must match `rust/`.
  - Phase 4 ➜ CWD must match `emulator/`.
  - Mismatch ⇒ emit `::error::Please cd into the correct module directory` and `exit 1`.

Reason: Prevents accidentally compiling the wrong subtree.

---

## 3. Slash Command argument-hint Metadata

Add YAML front-matter block to every command script in `ci/scripts/slash/`:

```bash
# ---
# argument-hint: "<job>|<phase>|<hours>"
# ---
```

Claude surfaces this hint for tab-completion & tool-tips.
- Convention — use the pipe (`|`) to list mutually exclusive placeholders.

Examples:
```bash
# argument-hint: "<job>"
# argument-hint: "<phase>"
# argument-hint: "<since> (e.g. 24h|7d)"
```

---

## 4. In-Memory Shell Snapshot on File Errors

If any `PostToolUse` analyzer fails to open a `build.log` (or similar):

```bash
claude shell snapshot --since-error \
  | gzip > "docs/ci-status/snapshots/${RUN_ID}.gz"
status-append.py "shell_snapshot" "${RUN_ID}.gz"
```

- Only trigger once per `RUN_ATTEMPT` to avoid bloat.
- Snapshot retention follows the same 30-day rotation as pipeline logs.

---

## 5. Roll-out Checklist

| Task | Owner | Status |
|------|-------|--------|
| Add UserPromptSubmit router module | @ci-core | ☐ |
| Update validators to use $CCODE_CWD | @build | ☐ |
| Insert argument-hint blocks | @dx-team | ☐ |
| Wire shell-snapshot into analyze-build.sh | @reliability | ☐ |

Once all tasks tick ✅, bump `CI_CONFIG_VERSION` to `2.1` so downstream scripts know features are available.