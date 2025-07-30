#!/bin/bash
# hooks/dispatcher.d/pre-tool-use/validate-file-creation.sh
#
# Purpose: Validate file creation to prevent unnecessary files
# Warns about root directory files and tracks all file creation

# Only check Write tool usage
if [[ "$TOOL_NAME" != "Write" ]]; then
    exit 0
fi

# Extract file path from payload
FILE_PATH=$(echo "$PAYLOAD" | jq -r '.tool_args.file_path // empty')

# If no file path, exit
if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

echo "[$(date)] Validating file creation: $FILE_PATH"

# Make path relative if it starts with project root
PROJECT_ROOT="$(pwd)"
RELATIVE_PATH="${FILE_PATH#$PROJECT_ROOT/}"

# Check if creating in root directory (no slashes in relative path)
if [[ ! "$RELATIVE_PATH" =~ / ]]; then
    echo "[WARNING] ⚠️  Attempting to create file in root directory: $FILE_PATH"
    echo "[WARNING] Consider placing in appropriate subdirectory:"
    echo "[WARNING]   - Scripts: ci/scripts/"
    echo "[WARNING]   - Hooks: hooks/dispatcher.d/"
    echo "[WARNING]   - Documentation: docs/"
    echo "[WARNING]   - Tests: tests/"
fi

# Check for common unnecessary files
if [[ "$FILE_PATH" =~ \.(tmp|test|bak|swp|DS_Store)$ ]]; then
    echo "[WARNING] ⚠️  Creating temporary/backup file: $FILE_PATH"
    echo "[WARNING] Remember to clean up temporary files"
fi

# Check for documentation files being created without request
if [[ "$FILE_PATH" =~ \.md$ ]] && [[ "$FILE_PATH" != *"CLAUDE.md"* ]] && [[ "$FILE_PATH" != *"GEMINI.md"* ]]; then
    echo "[INFO] 📝 Creating documentation file: $FILE_PATH"
    echo "[INFO] Ensure this was explicitly requested by the user"
fi

# Create audit directory if needed
AUDIT_DIR=".claude/file-creation-audit"
mkdir -p "$AUDIT_DIR"

# Log file creation for audit (with rotation)
AUDIT_LOG="$AUDIT_DIR/$(date +%Y%m).log"
echo "[$(date +%Y-%m-%d\ %H:%M:%S)] CREATE: $FILE_PATH" >> "$AUDIT_LOG"

# Check if file already exists
if [[ -f "$FILE_PATH" ]]; then
    echo "[INFO] ℹ️  File already exists and will be overwritten: $FILE_PATH"
fi

echo "[$(date)] File creation validation complete"