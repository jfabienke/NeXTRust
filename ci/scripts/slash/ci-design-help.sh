#!/usr/bin/env bash
# ci/scripts/slash/ci-design-help.sh - Slash command for O3 design assistance
#
# Usage: /ci-design-help [--error "error"] [--phase phase] [--prompt "question"]
# Purpose: Request O3 design guidance for complex problems
#
set -euo pipefail

echo "🎨 O3 Design Assistant Slash Command"
echo "===================================="

# Default values
ERROR=""
PHASE=""
PROMPT=""
FORCE_REQUEST="false"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --error)
            ERROR="$2"
            shift 2
            ;;
        --phase)
            PHASE="$2"
            shift 2
            ;;
        --prompt)
            PROMPT="$2"
            shift 2
            ;;
        --force)
            FORCE_REQUEST="true"
            shift
            ;;
        --help|-h)
            cat << 'EOF'
O3 Design Assistant Slash Command

Usage: /ci-design-help [options]

Options:
  --error <text>     Specific error or problem to analyze
  --phase <phase>    Current project phase context
  --prompt <text>    Custom design question or request
  --force            Force request even if similar was made recently
  --help             Show this help message

Examples:
  /ci-design-help --error "LLVM linker fails with undefined symbols"
  /ci-design-help --phase llvm-enhancement --prompt "Best approach for M68k atomics?"
  /ci-design-help --prompt "How to structure the emulation test framework?"

This command uses OpenAI O3 for deep technical design guidance.
Costs ~$0.10-$1.00 per request, so use thoughtfully.

The assistant will analyze your specific problem and provide:
- Root cause analysis
- Multiple solution approaches
- Implementation recommendations
- Risk assessment and mitigation strategies
EOF
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            # Treat remaining args as part of the prompt
            PROMPT="$PROMPT $*"
            break
            ;;
    esac
done

# Get current phase if not specified
if [[ -z "$PHASE" ]]; then
    if [[ -f "docs/ci-status/pipeline-log.json" ]]; then
        PHASE=$(jq -r '.current_phase.id // "unknown"' docs/ci-status/pipeline-log.json 2>/dev/null || echo "unknown")
    else
        PHASE="unknown"
    fi
fi

# Check if we have something to ask about
if [[ -z "$ERROR" && -z "$PROMPT" ]]; then
    echo "❌ Error: Must specify either --error or --prompt"
    echo "Use --help for usage examples"
    exit 1
fi

echo "📋 Design Request Configuration:"
echo "  Phase: $PHASE"
[[ -n "$ERROR" ]] && echo "  Error: $ERROR"
[[ -n "$PROMPT" ]] && echo "  Prompt: $PROMPT"

# Check for rate limiting (don't make too many O3 requests)
if [[ "$FORCE_REQUEST" != "true" ]]; then
    # Check if we've made recent O3 requests
    recent_requests=0
    if [[ -f "docs/ci-status/metrics/pipeline-metrics-$(date +%Y-%m).jsonl" ]]; then
        recent_requests=$(grep -c "o3.*design" "docs/ci-status/metrics/pipeline-metrics-$(date +%Y-%m).jsonl" 2>/dev/null || echo 0)
    fi
    
    if [[ $recent_requests -gt 10 ]]; then
        echo "⚠️  Rate limit warning: $recent_requests O3 requests made this month"
        echo "💰 Each request costs ~$0.10-$1.00. Continue? (y/N)"
        read -r confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Request cancelled"
            exit 0
        fi
    fi
fi

# Build context for O3
context_data=""
if [[ -n "$ERROR" ]]; then
    context_data="error_analysis:$PHASE"
elif [[ -n "$PROMPT" ]]; then
    context_data="design_question:$PHASE"
fi

echo "🧠 Sending request to O3 design assistant..."
echo "💰 Estimated cost: $0.10-$1.00"

# Use the unified AI service handler
START_TIME=$(date +%s)

if ./ci/scripts/request-ai-service.sh \
    --service o3 \
    --type design \
    --context "$context_data" \
    ${PROMPT:+--prompt "$PROMPT"}; then
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo "✅ O3 design guidance completed in ${DURATION}s"
    
    # Log successful request
    if [[ -f "hooks/dispatcher.d/common/metrics.sh" ]]; then
        source hooks/dispatcher.d/common/metrics.sh
        emit_counter "slash_command" 1 "command:design-help,service:o3"
        emit_counter "manual_o3_request" 1 "phase:$PHASE,type:${ERROR:+error}${PROMPT:+prompt}"
        emit_timing "o3_design_request" "$DURATION" "phase:$PHASE"
        
        # Rough cost tracking (estimate $0.50 per request)
        emit_ai_usage "o3" 1000 2000 0.50 "phase:$PHASE,type:manual"
    fi
    
else
    echo "❌ O3 design request failed"
    echo "💡 Common issues:"
    echo "  - API key not configured (check OPENAI_API_KEY)"
    echo "  - Rate limits exceeded"
    echo "  - Budget limits reached"
    exit 1
fi

echo ""
echo "📊 Design consultation completed via slash command"
echo "💡 Tip: Use '/ci-help' to see all available slash commands"
echo "💰 Remember: O3 requests have cost implications - use thoughtfully"