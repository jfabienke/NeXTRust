#!/usr/bin/env bash
# ci/scripts/slash/ci-ai-review.sh - Slash command for requesting AI code reviews
#
# Usage: /ci-ai-review [--service gemini|o3] [--context phase] [files...]
# Purpose: Manual trigger for AI code reviews via slash commands
#
set -euo pipefail

echo "🤖 AI Code Review Slash Command"
echo "================================"

# Default values
SERVICE="gemini"
CONTEXT=""
FILES=()
PROMPT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --service)
            SERVICE="$2"
            shift 2
            ;;
        --context)
            CONTEXT="$2"
            shift 2
            ;;
        --prompt)
            PROMPT="$2"
            shift 2
            ;;
        --help|-h)
            cat << 'EOF'
AI Code Review Slash Command

Usage: /ci-ai-review [options] [files...]

Options:
  --service <gemini|o3>    AI service to use (default: gemini)
  --context <phase>        Phase context for the review
  --prompt <text>          Custom prompt for the review
  --help                   Show this help message

Examples:
  /ci-ai-review                              # Review recent changes with Gemini
  /ci-ai-review --service o3 --context llvm # O3 design review for LLVM phase  
  /ci-ai-review src/*.rs                     # Review specific Rust files
  /ci-ai-review --prompt "Focus on memory safety"

Supported services:
  - gemini: Fast code reviews, best for implementation feedback
  - o3: Deep design analysis, best for architecture decisions

The review will be posted as output and optionally to PR comments if in CI.
EOF
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            FILES+=("$1")
            shift
            ;;
    esac
done

# Validate service
if [[ "$SERVICE" != "gemini" && "$SERVICE" != "o3" ]]; then
    echo "❌ Error: Service must be 'gemini' or 'o3'"
    exit 1
fi

# Get current phase if not specified
if [[ -z "$CONTEXT" ]]; then
    if [[ -f "docs/ci-status/pipeline-log.json" ]]; then
        CONTEXT=$(jq -r '.current_phase.id // "current"' docs/ci-status/pipeline-log.json 2>/dev/null || echo "current")
    else
        CONTEXT="current"
    fi
fi

echo "📋 Review Configuration:"
echo "  Service: $SERVICE"
echo "  Context: $CONTEXT"
echo "  Files: ${#FILES[@]} specified"

# If no files specified, get recent changes
if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "📁 No specific files provided - detecting recent changes..."
    
    # Try to get files from current branch vs main
    if git rev-parse --verify origin/main >/dev/null 2>&1; then
        while IFS= read -r line; do
            FILES+=("$line")
        done < <(git diff --name-only origin/main...HEAD 2>/dev/null || echo "")
    else
        # Fallback to last commit
        while IFS= read -r line; do
            FILES+=("$line")
        done < <(git diff --name-only HEAD~1 2>/dev/null || echo "")
    fi
    
    if [[ ${#FILES[@]} -eq 0 ]]; then
        echo "❌ No changes detected. Specify files manually or make some changes first."
        exit 1
    fi
    
    echo "  Detected ${#FILES[@]} changed files"
fi

# Filter files to existing ones
EXISTING_FILES=()
for file in "${FILES[@]}"; do
    if [[ -f "$file" ]]; then
        EXISTING_FILES+=("$file")
    else
        echo "⚠️  File not found: $file"
    fi
done

if [[ ${#EXISTING_FILES[@]} -eq 0 ]]; then
    echo "❌ No existing files to review"
    exit 1
fi

echo "✅ Found ${#EXISTING_FILES[@]} files to review"

# Build request based on service type
case "$SERVICE" in
    gemini)
        echo "🧠 Requesting Gemini code review..."
        
        # Use the unified AI service handler
        if ./ci/scripts/request-ai-service.sh \
            --service gemini \
            --type review \
            --context "$CONTEXT" \
            --review-context "Manual slash command review" \
            ${PROMPT:+--prompt "$PROMPT"}; then
            
            echo "✅ Gemini review completed successfully"
        else
            echo "❌ Gemini review failed"
            exit 1
        fi
        ;;
        
    o3)
        echo "🧠 Requesting O3 design analysis..."
        
        # For O3, we need to format as a design request
        local design_context="manual_review:$CONTEXT"
        
        if ./ci/scripts/request-ai-service.sh \
            --service o3 \
            --type design \
            --context "$design_context" \
            ${PROMPT:+--prompt "$PROMPT"}; then
            
            echo "✅ O3 design analysis completed successfully"
        else
            echo "❌ O3 design analysis failed"
            exit 1
        fi
        ;;
esac

# Emit usage metrics
if [[ -f "hooks/dispatcher.d/common/metrics.sh" ]]; then
    source hooks/dispatcher.d/common/metrics.sh
    emit_counter "slash_command" 1 "command:ai-review,service:$SERVICE"
    emit_counter "manual_ai_review" 1 "service:$SERVICE,context:$CONTEXT"
fi

echo "📊 Review completed via slash command"
echo "💡 Tip: Use '/ci-help' to see all available slash commands"