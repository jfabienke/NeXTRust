#!/usr/bin/env bash
# ci/scripts/analyze-claude-usage.sh - Analyze Claude Code usage with ccusage
#
# Purpose: Use ccusage (https://github.com/ryoppippi/ccusage) to analyze token usage
# This provides cost analysis from Claude Code's local JSONL files
#
set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
REPORT_TYPE="${1:-daily}"
OUTPUT_FORMAT="${2:-human}"

echo -e "${BLUE}=== Claude Code Usage Analysis ===${NC}"
echo "Report type: $REPORT_TYPE"
echo

# Check if we have npx or bunx available
if command -v bunx &>/dev/null; then
    RUNNER="bunx"
elif command -v npx &>/dev/null; then
    RUNNER="npx"
else
    echo -e "${RED}Error: Neither bunx nor npx found${NC}"
    echo "Please install Node.js or Bun to use ccusage"
    exit 1
fi

# Function to run ccusage with error handling
run_ccusage() {
    local cmd="$1"
    local args="${2:-}"
    
    echo -e "${YELLOW}Running: $RUNNER ccusage@latest $cmd $args${NC}"
    echo
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        $RUNNER ccusage@latest $cmd $args --json 2>/dev/null || {
            echo -e "${RED}Failed to run ccusage${NC}"
            return 1
        }
    else
        $RUNNER ccusage@latest $cmd $args 2>/dev/null || {
            echo -e "${RED}Failed to run ccusage${NC}"
            return 1
        }
    fi
}

# Main execution based on report type
case "$REPORT_TYPE" in
    daily)
        echo -e "${GREEN}Daily Token Usage Report${NC}"
        echo "─────────────────────────"
        run_ccusage "daily"
        ;;
        
    monthly)
        echo -e "${GREEN}Monthly Token Usage Report${NC}"
        echo "──────────────────────────"
        run_ccusage "monthly"
        ;;
        
    session)
        echo -e "${GREEN}Session-based Usage Report${NC}"
        echo "──────────────────────────"
        run_ccusage "blocks"
        ;;
        
    active)
        echo -e "${GREEN}Active Session Monitor${NC}"
        echo "─────────────────────"
        echo "Shows current active session with projections"
        echo
        run_ccusage "blocks" "--active"
        ;;
        
    recent)
        echo -e "${GREEN}Recent Sessions (Last 3 Days)${NC}"
        echo "────────────────────────────"
        run_ccusage "blocks" "--recent"
        ;;
        
    cost)
        echo -e "${GREEN}Cost Analysis${NC}"
        echo "─────────────"
        # Get daily costs for the last 7 days
        echo "Last 7 days:"
        run_ccusage "daily" "--days 7"
        ;;
        
    export)
        # Export usage data as JSON
        echo -e "${GREEN}Exporting usage data as JSON...${NC}"
        OUTPUT_FILE="claude-usage-$(date +%Y%m%d).json"
        
        if run_ccusage "daily" "--days 30" > "$OUTPUT_FILE"; then
            echo -e "${GREEN}✓${NC} Exported to: $OUTPUT_FILE"
            echo "  Size: $(wc -c < "$OUTPUT_FILE") bytes"
            echo "  Preview:"
            head -5 "$OUTPUT_FILE" | sed 's/^/    /'
        else
            rm -f "$OUTPUT_FILE"
            exit 1
        fi
        ;;
        
    help|--help|-h)
        echo "Usage: $0 [report_type] [output_format]"
        echo
        echo "Report types:"
        echo "  daily    - Show daily token usage (default)"
        echo "  monthly  - Show monthly aggregated usage"
        echo "  session  - Show session-based usage blocks"
        echo "  active   - Show active session with projections"
        echo "  recent   - Show sessions from last 3 days"
        echo "  cost     - Cost analysis for recent usage"
        echo "  export   - Export usage data as JSON"
        echo
        echo "Output formats:"
        echo "  human    - Human-readable format (default)"
        echo "  json     - JSON format for processing"
        echo
        echo "Examples:"
        echo "  $0                    # Daily report"
        echo "  $0 monthly           # Monthly summary"
        echo "  $0 cost              # Cost analysis"
        echo "  $0 daily json        # Daily report as JSON"
        echo "  $0 export            # Export data to file"
        ;;
        
    *)
        echo -e "${RED}Unknown report type: $REPORT_TYPE${NC}"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac

# Add summary note
if [[ "$REPORT_TYPE" != "help" ]] && [[ "$REPORT_TYPE" != "live" ]]; then
    echo
    echo -e "${BLUE}Note:${NC} This analyzes Claude Code's local usage data."
    echo "For more details, visit: https://ccusage.com"
fi