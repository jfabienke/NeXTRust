#!/usr/bin/env bash
# ci/scripts/test-all-cpu-models.sh - Test Rust compilation with all M68k CPU models
#
# Purpose: Verify that cargo build works with each supported M68k CPU variant
# Usage: ./ci/scripts/test-all-cpu-models.sh
#
set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# CPU models to test
CPU_MODELS=(
    "generic"
    "M68000"
    "M68010"
    "M68020"
    "M68030"
    "M68040"
    "M68060"
)

# Project paths
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_DIR="$PROJECT_ROOT/targets"
EXAMPLES_DIR="$PROJECT_ROOT/src/examples"
ORIGINAL_TARGET="$TARGET_DIR/m68k-next-nextstep.json"
TEST_RESULTS_DIR="$PROJECT_ROOT/docs/ci-status/test-results/cpu-models"

# Create test results directory
mkdir -p "$TEST_RESULTS_DIR"

echo "=========================================="
echo "Testing M68k CPU Models for NeXTRust"
echo "=========================================="
echo "Date: $(date)"
echo ""

# Function to test a specific CPU model
test_cpu_model() {
    local cpu_model="$1"
    local target_file="$TARGET_DIR/m68k-next-nextstep-${cpu_model}.json"
    local log_file="$TEST_RESULTS_DIR/build-${cpu_model}-$(date +%Y%m%d-%H%M%S).log"
    
    echo -n "Testing CPU model: ${cpu_model}... "
    
    # Create CPU-specific target JSON
    if [[ -f "$ORIGINAL_TARGET" ]]; then
        # Update the CPU field in the target JSON
        jq --arg cpu "$cpu_model" '.cpu = $cpu' "$ORIGINAL_TARGET" > "$target_file"
    else
        echo -e "${RED}ERROR: Original target file not found${NC}"
        return 1
    fi
    
    # Attempt to build with the CPU-specific target
    cd "$EXAMPLES_DIR"
    if cargo +nightly build \
        --target="$target_file" \
        -Z build-std=core \
        --verbose \
        > "$log_file" 2>&1; then
        
        echo -e "${GREEN}SUCCESS${NC}"
        
        # Extract and display build time
        local build_time=$(grep "Finished" "$log_file" | tail -1 | grep -oE '[0-9]+\.[0-9]+s' || echo "N/A")
        echo "  Build time: $build_time"
        
        # Check if object files were generated
        local obj_count=$(find "$PROJECT_ROOT/target/m68k-next-nextstep/debug" -name "*.o" 2>/dev/null | wc -l)
        echo "  Object files generated: $obj_count"
        
        # Record success
        echo "{
  \"cpu_model\": \"$cpu_model\",
  \"status\": \"success\",
  \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",
  \"build_time\": \"$build_time\",
  \"object_files\": $obj_count
}" > "$TEST_RESULTS_DIR/${cpu_model}-result.json"
        
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        
        # Extract error message
        local error_msg=$(grep -E "(error|LLVM ERROR|panic|SIGSEGV)" "$log_file" | head -5 | tr '\n' ' ')
        echo "  Error: ${error_msg:0:100}..."
        
        # Record failure
        echo "{
  \"cpu_model\": \"$cpu_model\",
  \"status\": \"failed\",
  \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",
  \"error\": \"$error_msg\"
}" > "$TEST_RESULTS_DIR/${cpu_model}-result.json"
        
        return 1
    fi
}

# Main test loop
PASSED=0
FAILED=0

for cpu in "${CPU_MODELS[@]}"; do
    if test_cpu_model "$cpu"; then
        ((PASSED++))
    else
        ((FAILED++))
    fi
    echo ""
done

# Summary
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo ""

# Generate summary report
SUMMARY_FILE="$TEST_RESULTS_DIR/summary-$(date +%Y%m%d-%H%M%S).json"
echo "{
  \"test_date\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",
  \"total_models\": ${#CPU_MODELS[@]},
  \"passed\": $PASSED,
  \"failed\": $FAILED,
  \"results\": [" > "$SUMMARY_FILE"

# Add individual results to summary
FIRST=true
for cpu in "${CPU_MODELS[@]}"; do
    if [[ -f "$TEST_RESULTS_DIR/${cpu}-result.json" ]]; then
        if [[ "$FIRST" != "true" ]]; then
            echo "," >> "$SUMMARY_FILE"
        fi
        cat "$TEST_RESULTS_DIR/${cpu}-result.json" >> "$SUMMARY_FILE"
        FIRST=false
    fi
done

echo "
  ]
}" >> "$SUMMARY_FILE"

echo "Full results saved to: $TEST_RESULTS_DIR"
echo ""

# Cleanup temporary target files
echo "Cleaning up temporary target files..."
for cpu in "${CPU_MODELS[@]}"; do
    rm -f "$TARGET_DIR/m68k-next-nextstep-${cpu}.json"
done

# Exit with appropriate code
if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}All CPU models passed!${NC}"
    exit 0
else
    echo -e "${YELLOW}Some CPU models failed. Please check the logs for details.${NC}"
    exit 1
fi