#!/bin/bash
# hooks/dispatcher.d/common/90-phase-complete.sh - Phase completion hook
#
# Purpose: Trigger AI services when a phase reaches 90% completion
# Called by: dispatcher.sh when phase progress >= 0.9
#
set -euo pipefail

# Function to check if phase is 90%+ complete
check_phase_completion() {
    local phase_id="$1"
    local completion_threshold="${2:-0.9}"
    
    if [[ ! -f "docs/ci-status/pipeline-log.json" ]]; then
        echo "Pipeline log not found"
        return 1
    fi
    
    # Get current phase progress
    local progress=$(jq -r --arg phase "$phase_id" \
        '.phases[] | select(.id == $phase) | .progress // 0' \
        docs/ci-status/pipeline-log.json 2>/dev/null || echo "0")
    
    # Compare with threshold (using awk for floating point)
    if awk -v prog="$progress" -v thresh="$completion_threshold" 'BEGIN { exit (prog >= thresh ? 0 : 1) }'; then
        return 0  # Phase is 90%+ complete
    else
        return 1  # Phase not yet complete enough
    fi
}

# Function to trigger appropriate AI service based on phase
trigger_ai_service() {
    local phase_id="$1"
    local phase_name="$2"
    
    echo "[$(date)] Phase $phase_id ($phase_name) is 90% complete - triggering AI services"
    
    case "$phase_id" in
        "llvm-enhancement"|"rust-target"|"emulation-setup")
            # Technical implementation phases - request Gemini review
            echo "Requesting Gemini technical review for phase: $phase_name"
            if [[ -x "ci/scripts/request-ai-service.sh" ]]; then
                ./ci/scripts/request-ai-service.sh \
                    --service gemini \
                    --type review \
                    --context "$phase_id" \
                    --review-context "Phase completion review: $phase_name" \
                    || echo "Warning: Gemini review request failed"
            fi
            ;;
            
        "system-setup"|"ci-integration")
            # Infrastructure phases - request O3 design validation
            echo "Requesting O3 design validation for phase: $phase_name"
            if [[ -x "ci/scripts/request-ai-service.sh" ]]; then
                ./ci/scripts/request-ai-service.sh \
                    --service o3 \
                    --type design \
                    --context "phase_completion:$phase_id" \
                    || echo "Warning: O3 design request failed"
            fi
            ;;
            
        "final-review")
            # Final phase - trigger both services
            echo "Final phase completion - requesting comprehensive review"
            
            # Gemini for code review
            if [[ -x "ci/scripts/request-ai-service.sh" ]]; then
                ./ci/scripts/request-ai-service.sh \
                    --service gemini \
                    --type review \
                    --context "$phase_id" \
                    --review-context "Final project review" &
                    
                # O3 for final architecture validation
                ./ci/scripts/request-ai-service.sh \
                    --service o3 \
                    --type design \
                    --context "final_validation:$phase_id" &
                    
                wait  # Wait for both to complete
            fi
            ;;
            
        *)
            echo "No specific AI service configured for phase: $phase_id"
            ;;
    esac
}

# Function to update phase status after AI completion
update_phase_status() {
    local phase_id="$1"
    local ai_feedback="$2"
    
    if [[ -x "ci/scripts/status-append.py" ]]; then
        python3 ci/scripts/status-append.py "ai_phase_review" \
            "{\"phase_id\": \"$phase_id\", \"ai_feedback\": \"$ai_feedback\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
            || echo "Warning: Failed to update pipeline status"
    fi
    
    # Emit metrics for monitoring
    if [[ -f "hooks/dispatcher.d/common/metrics.sh" ]]; then
        source hooks/dispatcher.d/common/metrics.sh
        emit_counter "phase_ai_review" 1 "phase:$phase_id"
    fi
}

# Main execution
main() {
    local phase_id="${1:-}"
    local force_trigger="${2:-false}"
    
    # Get current phase if not specified
    if [[ -z "$phase_id" ]]; then
        if [[ -f "docs/ci-status/pipeline-log.json" ]]; then
            phase_id=$(jq -r '.current_phase.id // "unknown"' docs/ci-status/pipeline-log.json 2>/dev/null || echo "unknown")
        else
            echo "No phase specified and pipeline log not found"
            exit 1
        fi
    fi
    
    # Get phase name
    local phase_name="unknown"
    if [[ -f "docs/ci-status/pipeline-log.json" ]]; then
        phase_name=$(jq -r --arg phase "$phase_id" \
            '.phases[] | select(.id == $phase) | .name // "Unknown"' \
            docs/ci-status/pipeline-log.json 2>/dev/null || echo "Unknown")
    fi
    
    echo "[$(date)] Checking completion for phase: $phase_id ($phase_name)"
    
    # Check if we should trigger AI services
    if [[ "$force_trigger" == "true" ]] || check_phase_completion "$phase_id"; then
        trigger_ai_service "$phase_id" "$phase_name"
        
        # Log the trigger event
        echo "[$(date)] AI services triggered for phase $phase_id"
        
        # Update metrics
        if [[ -f "hooks/dispatcher.d/common/metrics.sh" ]]; then
            source hooks/dispatcher.d/common/metrics.sh
            emit_counter "phase_completion_trigger" 1 "phase:$phase_id"
        fi
    else
        echo "[$(date)] Phase $phase_id not yet 90% complete - skipping AI trigger"
    fi
}

# Allow direct execution with parameters
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi