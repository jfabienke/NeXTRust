#!/usr/bin/env bash
# ci/scripts/lint-gemini-md.sh - Lint GEMINI.md for freshness and correctness
#
# Purpose: Ensure GEMINI.md remains up-to-date and properly formatted
# Usage: ./ci/scripts/lint-gemini-md.sh
#
set -euo pipefail

GEMINI_FILE="GEMINI.md"
EXIT_CODE=0

echo "=== Linting GEMINI.md ==="
echo

# Check if file exists
if [[ ! -f "$GEMINI_FILE" ]]; then
    echo "❌ ERROR: $GEMINI_FILE not found"
    exit 1
fi

# Function to extract metadata
extract_metadata() {
    local key=$1
    grep -E "^<!-- $key: .+ -->$" "$GEMINI_FILE" | sed -E "s/<!-- $key: (.+) -->/\1/" || echo ""
}

# 1. Check version format
echo "1. Checking version format..."
VERSION=$(extract_metadata "GEMINI-VERSION")
if [[ -z "$VERSION" ]]; then
    echo "   ❌ Missing GEMINI-VERSION metadata"
    EXIT_CODE=1
elif [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "   ❌ Invalid version format: $VERSION (expected: X.Y.Z)"
    EXIT_CODE=1
else
    echo "   ✅ Version: $VERSION"
fi
echo

# 2. Check freshness
echo "2. Checking freshness..."
LAST_MODIFIED=$(extract_metadata "LAST-MODIFIED")
UPDATE_HORIZON=$(extract_metadata "AUTO-UPDATE-HORIZON")

if [[ -z "$LAST_MODIFIED" ]]; then
    echo "   ❌ Missing LAST-MODIFIED metadata"
    EXIT_CODE=1
elif [[ -z "$UPDATE_HORIZON" ]]; then
    echo "   ❌ Missing AUTO-UPDATE-HORIZON metadata"
    EXIT_CODE=1
else
    # Parse horizon (e.g., "90d" -> 90 days)
    HORIZON_DAYS=$(echo "$UPDATE_HORIZON" | sed 's/d$//')
    
    # Calculate age
    if date --version >/dev/null 2>&1; then
        # GNU date
        LAST_MODIFIED_EPOCH=$(date -d "$LAST_MODIFIED" +%s 2>/dev/null || echo 0)
        CURRENT_EPOCH=$(date +%s)
    else
        # BSD date (macOS)
        LAST_MODIFIED_EPOCH=$(date -j -f "%Y-%m-%d" "$LAST_MODIFIED" +%s 2>/dev/null || echo 0)
        CURRENT_EPOCH=$(date +%s)
    fi
    
    if [[ $LAST_MODIFIED_EPOCH -eq 0 ]]; then
        echo "   ❌ Invalid LAST-MODIFIED date format: $LAST_MODIFIED"
        EXIT_CODE=1
    else
        AGE_DAYS=$(( (CURRENT_EPOCH - LAST_MODIFIED_EPOCH) / 86400 ))
        
        if [[ $AGE_DAYS -gt $HORIZON_DAYS ]]; then
            echo "   ❌ Document is stale: $AGE_DAYS days old (limit: $HORIZON_DAYS days)"
            echo "      Please review and update the content, then update LAST-MODIFIED"
            EXIT_CODE=1
        else
            echo "   ✅ Document is fresh: $AGE_DAYS days old (limit: $HORIZON_DAYS days)"
        fi
    fi
fi
echo

# 3. Check required sections
echo "3. Checking required sections..."
REQUIRED_SECTIONS=(
    "Token Budget Awareness"
    "Review Context"
    "Project Overview"
    "Review Checklist"
    "Phase-Specific Guidelines"
    "Red Flags to Highlight"
    "Positive Patterns to Acknowledge"
    "Review Output Format"
)

for section in "${REQUIRED_SECTIONS[@]}"; do
    if grep -q "^## $section" "$GEMINI_FILE"; then
        echo "   ✅ Found section: $section"
    else
        echo "   ❌ Missing section: $section"
        EXIT_CODE=1
    fi
done
echo

# 4. Check version consistency
echo "4. Checking version consistency..."
VERSION_IN_OUTPUT=$(grep -A5 "^## Review Output Format" "$GEMINI_FILE" | grep "GEMINI.md Version:" | sed -E 's/.*Version: ([0-9.]+).*/\1/' || echo "")

if [[ -z "$VERSION_IN_OUTPUT" ]]; then
    echo "   ❌ Version not found in output format section"
    EXIT_CODE=1
elif [[ "$VERSION" != "$VERSION_IN_OUTPUT" ]]; then
    echo "   ❌ Version mismatch: metadata=$VERSION, output=$VERSION_IN_OUTPUT"
    EXIT_CODE=1
else
    echo "   ✅ Version consistent: $VERSION"
fi
echo

# 5. Check for CI-specific guidelines
echo "5. Checking CI-specific guidelines..."
CI_CHECKS=(
    "status-append.py"
    "ccusage"
    "CI Pipeline Integration"
    "Hook-based orchestration"
)

MISSING_CI_CHECKS=0
for check in "${CI_CHECKS[@]}"; do
    if grep -q "$check" "$GEMINI_FILE"; then
        echo "   ✅ Found CI reference: $check"
    else
        echo "   ❌ Missing CI reference: $check"
        MISSING_CI_CHECKS=$((MISSING_CI_CHECKS + 1))
    fi
done

if [[ $MISSING_CI_CHECKS -gt 0 ]]; then
    EXIT_CODE=1
fi
echo

# 6. Check token efficiency warning
echo "6. Checking token efficiency..."
if grep -q "Token efficiency.*~.*tokens" "$GEMINI_FILE"; then
    echo "   ✅ Token efficiency warning present"
else
    echo "   ❌ Missing token efficiency warning in Reviewer Notes"
    EXIT_CODE=1
fi
echo

# 7. Size check
echo "7. Checking file size..."
FILE_SIZE=$(wc -c < "$GEMINI_FILE")
FILE_LINES=$(wc -l < "$GEMINI_FILE")

if [[ $FILE_SIZE -gt 10000 ]]; then
    echo "   ⚠️  Warning: File is large ($FILE_SIZE bytes)"
    echo "      Consider splitting into multiple focused documents"
elif [[ $FILE_LINES -gt 300 ]]; then
    echo "   ⚠️  Warning: File has many lines ($FILE_LINES lines)"
    echo "      Consider more concise guidelines"
else
    echo "   ✅ File size reasonable: $FILE_SIZE bytes, $FILE_LINES lines"
fi
echo

# Summary
echo "=== Lint Summary ==="
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "✅ All checks passed!"
    echo
    echo "Next maintenance date: $(date -d "$LAST_MODIFIED + $HORIZON_DAYS days" +%Y-%m-%d 2>/dev/null || echo "Check manually")"
else
    echo "❌ Some checks failed. Please fix the issues above."
    echo
    echo "To update freshness after making changes:"
    echo "  sed -i 's/<!-- LAST-MODIFIED: .* -->/<!-- LAST-MODIFIED: $(date +%Y-%m-%d) -->/' $GEMINI_FILE"
fi

exit $EXIT_CODE