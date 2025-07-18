#!/usr/bin/env bash
# ci/scripts/lint-claude-md.sh - Lint CLAUDE.md for freshness and correctness
#
# Purpose: Ensure CLAUDE.md remains up-to-date and properly formatted
# Usage: ./ci/scripts/lint-claude-md.sh
#
set -euo pipefail

CLAUDE_FILE="CLAUDE.md"
EXIT_CODE=0

echo "=== Linting CLAUDE.md ==="
echo

# Check if file exists
if [[ ! -f "$CLAUDE_FILE" ]]; then
    echo "❌ ERROR: $CLAUDE_FILE not found"
    exit 1
fi

# Function to extract freshness info
extract_freshness() {
    local last_line=$(tail -1 "$CLAUDE_FILE")
    if [[ "$last_line" =~ "Last updated:" ]]; then
        echo "$last_line"
    else
        echo ""
    fi
}

# 1. Check assistant persona section
echo "1. Checking assistant persona..."
if grep -q "### Assistant persona" "$CLAUDE_FILE"; then
    echo "   ✅ Assistant persona section found"
else
    echo "   ❌ Missing Assistant persona section"
    echo "      This is required for proper Claude Code grounding"
    EXIT_CODE=1
fi
echo

# 2. Check freshness
echo "2. Checking freshness..."
FRESHNESS_LINE=$(extract_freshness)

if [[ -z "$FRESHNESS_LINE" ]]; then
    echo "   ❌ Missing 'Last updated:' line at end of file"
    EXIT_CODE=1
elif [[ ! "$FRESHNESS_LINE" =~ "AUTO-UPDATE-HORIZON" ]]; then
    echo "   ❌ Missing AUTO-UPDATE-HORIZON marker"
    echo "      Add: <!-- AUTO-UPDATE-HORIZON:90d -->"
    EXIT_CODE=1
else
    # Extract date and horizon
    DATE_PART=$(echo "$FRESHNESS_LINE" | sed -E 's/.*Last updated: ([0-9-]+).*/\1/')
    HORIZON=$(echo "$FRESHNESS_LINE" | sed -E 's/.*AUTO-UPDATE-HORIZON:([0-9]+)d.*/\1/')
    
    # Calculate age
    if date --version >/dev/null 2>&1; then
        # GNU date
        LAST_MODIFIED_EPOCH=$(date -d "$DATE_PART" +%s 2>/dev/null || echo 0)
        CURRENT_EPOCH=$(date +%s)
    else
        # BSD date (macOS)
        LAST_MODIFIED_EPOCH=$(date -j -f "%Y-%m-%d" "$DATE_PART" +%s 2>/dev/null || echo 0)
        CURRENT_EPOCH=$(date +%s)
    fi
    
    if [[ $LAST_MODIFIED_EPOCH -eq 0 ]]; then
        echo "   ❌ Invalid date format in Last updated line"
        EXIT_CODE=1
    else
        AGE_DAYS=$(( (CURRENT_EPOCH - LAST_MODIFIED_EPOCH) / 86400 ))
        
        if [[ $AGE_DAYS -gt $HORIZON ]]; then
            echo "   ❌ Document is stale: $AGE_DAYS days old (limit: $HORIZON days)"
            echo "      Please review and update the content"
            EXIT_CODE=1
        else
            echo "   ✅ Document is fresh: $AGE_DAYS days old (limit: $HORIZON days)"
        fi
    fi
fi
echo

# 3. Check required sections
echo "3. Checking required sections..."
REQUIRED_SECTIONS=(
    "Project Overview"
    "Key Commands"
    "Architecture Overview"
    "Working with the Codebase"
)

for section in "${REQUIRED_SECTIONS[@]}"; do
    if grep -q "^## $section" "$CLAUDE_FILE"; then
        echo "   ✅ Found section: $section"
    else
        echo "   ❌ Missing section: $section"
        EXIT_CODE=1
    fi
done
echo

# 4. Check CI integration references
echo "4. Checking CI integration..."
CI_REFERENCES=(
    "status-append.py"
    "ccusage"
    "ci-help.sh"
    "slash commands"
)

MISSING_REFS=0
for ref in "${CI_REFERENCES[@]}"; do
    if grep -q "$ref" "$CLAUDE_FILE"; then
        echo "   ✅ Found reference: $ref"
    else
        echo "   ⚠️  Missing reference: $ref"
        MISSING_REFS=$((MISSING_REFS + 1))
    fi
done

if [[ $MISSING_REFS -gt 2 ]]; then
    echo "   ❌ Too many missing CI references"
    EXIT_CODE=1
fi
echo

# 5. Check token boundary hint
echo "5. Checking token management..."
if grep -q "150k tokens" "$CLAUDE_FILE"; then
    echo "   ✅ Token boundary hint present"
else
    echo "   ❌ Missing token boundary hint"
    echo "      Add guidance about handling large diffs/files"
    EXIT_CODE=1
fi
echo

# 6. Check cross-references
echo "6. Checking cross-references..."
if grep -q "GEMINI.md" "$CLAUDE_FILE"; then
    echo "   ✅ References GEMINI.md for review guidelines"
else
    echo "   ⚠️  Consider adding reference to GEMINI.md"
fi
echo

# 7. Size check
echo "7. Checking file size..."
FILE_SIZE=$(wc -c < "$CLAUDE_FILE")
FILE_LINES=$(wc -l < "$CLAUDE_FILE")

if [[ $FILE_SIZE -gt 8000 ]]; then
    echo "   ⚠️  Warning: File is getting large ($FILE_SIZE bytes)"
    echo "      Consider moving detailed sections to separate docs"
else
    echo "   ✅ File size reasonable: $FILE_SIZE bytes, $FILE_LINES lines"
fi
echo

# Summary
echo "=== Lint Summary ==="
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "✅ All checks passed!"
    echo
    echo "Next maintenance date: $(date -d "$DATE_PART + $HORIZON days" +%Y-%m-%d 2>/dev/null || echo "Check manually")"
else
    echo "❌ Some checks failed. Please fix the issues above."
    echo
    echo "To update freshness after making changes:"
    echo "  Update the last line with today's date"
fi

exit $EXIT_CODE