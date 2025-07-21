#!/usr/bin/env bash
# ci/scripts/request-ai-service.sh - Unified AI service request handler
#
# Purpose: Handle requests to various AI services (Gemini for reviews, O3 for design)
# Usage: ./ci/scripts/request-ai-service.sh --service <gemini|o3> --type <review|design> [--context <phase>]
#
set -uo pipefail

# Default values
SERVICE=""
REQUEST_TYPE=""
CONTEXT=""
REVIEW_CONTEXT=""
PR_NUMBER=""
PROMPT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --service)
            SERVICE="$2"
            shift 2
            ;;
        --type)
            REQUEST_TYPE="$2"
            shift 2
            ;;
        --context)
            CONTEXT="$2"
            shift 2
            ;;
        --review-context)
            REVIEW_CONTEXT="$2"
            shift 2
            ;;
        --pr)
            PR_NUMBER="$2"
            shift 2
            ;;
        --prompt)
            PROMPT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 --service <gemini|o3> --type <review|design> [--pr <number>] [--prompt <text>]"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$SERVICE" ]] || [[ -z "$REQUEST_TYPE" ]]; then
    echo "Error: --service and --type are required"
    echo "Usage: $0 --service <gemini|o3> --type <review|design> [--context <phase>]"
    exit 1
fi

echo "[$(date)] Starting $REQUEST_TYPE request to $SERVICE service..."

# Get current phase information
get_phase_info() {
    local phase_id="unknown"
    local phase_name="Unknown"
    
    if [[ -f "docs/ci-status/pipeline-log.json" ]]; then
        phase_id=$(jq -r '.current_phase.id // "unknown"' docs/ci-status/pipeline-log.json 2>/dev/null || echo "unknown")
        phase_name=$(jq -r '.current_phase.name // "Unknown"' docs/ci-status/pipeline-log.json 2>/dev/null || echo "Unknown")
    fi
    
    echo "$phase_id|$phase_name"
}

# Get changed files for review
get_changed_files() {
    local base_branch
    
    # Determine the base branch for comparison
    if git show-ref --verify --quiet refs/remotes/origin/main; then
        base_branch="origin/main"
    elif git show-ref --verify --quiet refs/remotes/origin/master; then
        base_branch="origin/master"
    else
        base_branch="origin/$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo 'main')"
    fi
    
    # Get changed files
    git diff --name-only "${base_branch}...HEAD" 2>/dev/null || git diff --name-only HEAD~1 2>/dev/null || echo ""
}

# Handle Gemini review requests
request_gemini_review() {
    local phase_info=$(get_phase_info)
    local phase_id=$(echo "$phase_info" | cut -d'|' -f1)
    local phase_name=$(echo "$phase_info" | cut -d'|' -f2)
    
    # Get changed files
    local changed_files=($(get_changed_files))
    
    if [[ ${#changed_files[@]} -eq 0 ]]; then
        echo "No file changes detected. Skipping review."
        return 0
    fi
    
    echo "Found ${#changed_files[@]} changed files for review"
    
    # Check if Gemini CLI is available
    if command -v gemini &> /dev/null; then
        echo "Using Gemini CLI for review..."
        use_gemini_cli "$phase_id" "$phase_name" "${changed_files[@]}"
    else
        echo "Gemini CLI not found, using gemini-cli-wrapper..."
        if [[ -x "ci/scripts/gemini-cli-wrapper.sh" ]]; then
            ./ci/scripts/gemini-cli-wrapper.sh "$phase_id" "$phase_name" "${changed_files[@]}"
        else
            echo "Error: No Gemini interface available"
            return 1
        fi
    fi
}

# Handle O3 design requests
request_o3_design() {
    local context="${CONTEXT:-$1}"
    local error="${2:-}"
    local custom_prompt="${PROMPT:-}"
    
    # Check if we've seen this before
    if [[ -f "docs/ci-status/known-issues.json" ]] && [[ -n "$error" ]]; then
        if jq -e --arg err "$error" '.known_issues[] | select(.error == $err)' docs/ci-status/known-issues.json >/dev/null 2>&1; then
            echo "Known issue - applying standard fix"
            return 0
        fi
    fi
    
    # Get phase info
    local phase_info=$(get_phase_info)
    local phase_id=$(echo "$phase_info" | cut -d'|' -f1)
    
    # Prepare design request
    local request=$(cat <<EOF
{
  "context": "$context",
  "error": "$error", 
  "phase": "$phase_id",
  "existing_attempts": $(jq --arg err "$error" '.activities | map(select(.details.error == $err)) | length' docs/ci-status/pipeline-log.json 2>/dev/null || echo 0)
}
EOF
)
    
    # Check if API is configured
    if [[ -z "${O3_ENDPOINT:-}" ]] || [[ -z "${OPENAI_API_KEY:-}" ]]; then
        echo "Warning: O3 API not configured, skipping design request"
        echo "Set O3_ENDPOINT and OPENAI_API_KEY environment variables to enable"
        return 0
    fi
    
    # Prepare content with proper escaping
    local user_content="${custom_prompt:-Context: $context\n\nError: $error\n\nPhase: $phase_id\n\nPlease analyze this issue and provide: 1) Root cause analysis, 2) Specific fix recommendations, 3) Code changes needed.}"
    
    # Escape the content for JSON
    user_content=$(echo "$user_content" | jq -Rs .)
    
    # Prepare O3 Responses API request
    # Use o3-mini for now, can switch to "o3" or "o3-2025-04-16" when org is verified
    local o3_request=$(cat <<EOF
{
  "model": "o3-mini",
  "input": $user_content
}
EOF
)
    
    # Call O3 Responses API
    echo "Requesting design decision from O3..."
    local response=$(curl -s -X POST "$O3_ENDPOINT/responses" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$o3_request")
    
    # Log decision
    if command -v python3 &>/dev/null && [[ -x "ci/scripts/status-append.py" || -x "$(which status-append.py 2>/dev/null)" ]]; then
        python3 ci/scripts/status-append.py "design_decision" \
            "{\"request\": $request, \"response\": $(echo "$response" | jq -c .)}" 2>/dev/null || true
    fi
    
    # Check for errors
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        echo "Error from O3 API:"
        echo "$response" | jq '.error' 2>/dev/null || echo "$response"
        return 1
    fi
    
    # Extract and display the response text
    echo "Design decision received:"
    echo "----------------------------------------"
    echo "$response" | jq -r '.output[] | select(.type == "message") | .content[] | select(.type == "output_text") | .text' 2>/dev/null || echo "$response"
    echo "----------------------------------------"
    
    # Show usage stats
    local total_tokens=$(echo "$response" | jq -r '.usage.total_tokens // 0' 2>/dev/null)
    local reasoning_tokens=$(echo "$response" | jq -r '.usage.output_tokens_details.reasoning_tokens // 0' 2>/dev/null)
    echo "Token usage: $total_tokens total (including $reasoning_tokens reasoning tokens)"
}

# Gemini CLI implementation
use_gemini_cli() {
    local phase_id="$1"
    local phase_name="$2"
    shift 2
    local files=("$@")
    
    # Check for GEMINI.md version
    local gemini_version="unknown"
    if [[ -f "GEMINI.md" ]]; then
        gemini_version=$(grep -oP 'GEMINI-VERSION:\s*\K[0-9.]+' GEMINI.md 2>/dev/null || echo "1.0.0")
    fi
    
    # Create prompt file
    local prompt_file="/tmp/gemini-review-prompt-$$.txt"
    
    cat << EOF > "$prompt_file"
Please provide a concise implementation review for the NeXTRust project.

Current Phase: $phase_name (ID: $phase_id)
Review Type: ${REVIEW_CONTEXT:-"Phase completion review"}
GEMINI.md Version: $gemini_version

Changed files to review:
EOF
    
    # Add files using @path syntax
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            echo "@$file" >> "$prompt_file"
        fi
    done
    
    # Add review request
    cat << 'EOF' >> "$prompt_file"

Please analyze these changes and provide feedback on:
1. Code quality and best practices
2. Potential bugs or issues
3. Alignment with project architecture
4. Suggestions for improvement

Focus on actionable feedback that can improve the implementation.
EOF
    
    # Source the wrapper for proper error handling
    source ci/scripts/gemini-cli-wrapper.sh
    
    # Execute Gemini with proper error handling
    echo "Executing Gemini review..."
    local temp_output="/tmp/gemini-review-$$"
    
    if gemini_review "$prompt_file" "$phase_id" "text" > "$temp_output" 2>&1; then
        echo "Review completed successfully"
        
        # Format for GitHub if in CI
        if [[ -n "${GITHUB_ACTIONS:-}" ]] && [[ -n "${CI_PR_NUMBER:-}" ]]; then
            local formatted_review=$(format_review_for_github "$(cat "$temp_output")" "$phase_name")
            
            # Post to PR
            gh api repos/${GITHUB_REPOSITORY}/issues/${CI_PR_NUMBER}/comments \
                -f body="$formatted_review" 2>/dev/null || echo "Failed to post review to PR"
        else
            # Just display the review
            cat "$temp_output"
        fi
        
        rm -f "$temp_output"
        rm -f "$prompt_file"
        return 0
    else
        echo "Review failed"
        cat "$temp_output" >&2
        rm -f "$temp_output"
        rm -f "$prompt_file"
        return 1
    fi
}

# PR-specific review handler
if [[ "$SERVICE" == "gemini" && "$REQUEST_TYPE" == "review" && -n "$PR_NUMBER" ]]; then
    echo "--- Requesting Gemini review for PR #${PR_NUMBER} ---"
    
    # Get changed files from the PR
    local changed_files=$(gh api repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/files --jq '.[].filename' 2>/dev/null || echo "")
    
    if [[ -z "$changed_files" ]]; then
        echo "No changed files found in PR #${PR_NUMBER}, using git diff fallback"
        changed_files=$(get_changed_files)
    fi
    
    # Build Gemini prompt with PR context
    local gemini_prompt=$(cat <<EOF
Please review the code changes in Pull Request #${PR_NUMBER} for the NeXTRust project.

${PROMPT:-"Focus on code quality, potential bugs, and alignment with the NeXTSTEP cross-compilation goals."}

Changed files:
$(echo "$changed_files" | head -10)

Please provide:
1. Overall assessment of the changes
2. Any potential issues or improvements
3. Specific feedback on critical sections
4. Recommendations for testing

Keep the review concise and actionable.
EOF
)
    
    # Call Gemini CLI or wrapper
    if command -v gemini &> /dev/null; then
        echo "$gemini_prompt" | gemini --model gemini-2.5-pro > /tmp/gemini-review-$$
    elif [[ -x "ci/scripts/gemini-cli-wrapper.sh" ]]; then
        echo "$gemini_prompt" | ./ci/scripts/gemini-cli-wrapper.sh > /tmp/gemini-review-$$
    else
        echo "Error: No Gemini interface available"
        exit 1
    fi
    
    # Post review as GitHub comment
    local review_content=$(cat /tmp/gemini-review-$$)
    local formatted_comment=$(cat <<EOF
## 🤖 Gemini Code Review

$review_content

---
*Automated review generated by Gemini 2.5 Pro*
EOF
)
    
    if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
        gh api repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments \
            -f body="$formatted_comment" \
            && echo "✅ Review posted to PR #${PR_NUMBER}" \
            || echo "❌ Failed to post review to PR #${PR_NUMBER}"
    else
        echo "Review generated but GITHUB_REPOSITORY not set - displaying locally:"
        echo "$formatted_comment"
    fi
    
    rm -f /tmp/gemini-review-$$
    exit 0
fi

# Main execution
case "$SERVICE" in
    gemini)
        if [[ "$REQUEST_TYPE" == "review" ]]; then
            request_gemini_review
        else
            echo "Error: Gemini service only supports 'review' type"
            exit 1
        fi
        ;;
    o3)
        if [[ "$REQUEST_TYPE" == "design" ]]; then
            request_o3_design "$CONTEXT"
        else
            echo "Error: O3 service only supports 'design' type"
            exit 1
        fi
        ;;
    *)
        echo "Error: Unknown service '$SERVICE'. Use 'gemini' or 'o3'"
        exit 1
        ;;
esac