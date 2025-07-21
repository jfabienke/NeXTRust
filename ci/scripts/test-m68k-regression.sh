#!/usr/bin/env bash
# ci/scripts/test-m68k-regression.sh - Regression test for M68k scheduling model
#
# Purpose: Ensure M68k-NeXTSTEP compilation continues to work after LLVM updates
# Usage: ./ci/scripts/test-m68k-regression.sh
#
set -euo pipefail

# Project paths
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXAMPLES_DIR="$PROJECT_ROOT/src/examples"
TEST_FILE="hello.rs"
TARGET_JSON="$PROJECT_ROOT/targets/m68k-next-nextstep.json"
LOG_DIR="$PROJECT_ROOT/docs/ci-status/test-results"

# Create log directory
mkdir -p "$LOG_DIR"

echo "=== M68k-NeXTSTEP Regression Test ==="
echo "Date: $(date)"
echo ""

# Function to run the test
run_regression_test() {
    local log_file="$LOG_DIR/m68k-regression-$(date +%Y%m%d-%H%M%S).log"
    
    echo "Running regression test..."
    echo "Test file: $TEST_FILE"
    echo "Target: m68k-next-nextstep"
    echo ""
    
    cd "$EXAMPLES_DIR"
    
    # Run the build using the same command that we know works
    if cargo +nightly build \
        --target="$TARGET_JSON" \
        -Z build-std=core \
        --verbose \
        > "$log_file" 2>&1; then
        
        echo "✅ PASS: Rust compilation succeeded"
        
        # Check if object files were created
        local obj_count=$(find "$PROJECT_ROOT/target/m68k-next-nextstep/debug" -name "*.o" 2>/dev/null | wc -l)
        if [[ $obj_count -gt 0 ]]; then
            echo "✅ PASS: $obj_count object files generated"
            
            # Check one of the object files
            local sample_obj=$(find "$PROJECT_ROOT/target/m68k-next-nextstep/debug" -name "*.o" 2>/dev/null | head -1)
            if [[ -n "$sample_obj" ]]; then
                local obj_format=$(file "$sample_obj" 2>/dev/null)
                if echo "$obj_format" | grep -qE "(Mach-O|ELF.*m68k)"; then
                    echo "✅ PASS: Object files are valid M68k format"
                    echo "  Format: $(echo "$obj_format" | cut -d: -f2)"
                else
                    echo "❌ FAIL: Object files are not valid M68k format"
                    echo "  Found: $obj_format"
                    return 1
                fi
            fi
        else
            echo "❌ FAIL: No object files generated"
            return 1
        fi
        
        # Extract metrics
        local build_time=$(grep "Finished" "$log_file" | tail -1 | grep -oE '[0-9]+\.[0-9]+s' || echo "N/A")
        echo ""
        echo "Build metrics:"
        echo "  Build time: $build_time"
        
        # Save result
        echo "{
  \"test\": \"m68k-regression\",
  \"status\": \"passed\",
  \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",
  \"build_time\": \"$build_time\",
  \"object_files\": $obj_count,
  \"log_file\": \"$log_file\"
}" > "$LOG_DIR/m68k-regression-latest.json"
        
        return 0
    else
        echo "❌ FAIL: Rust compilation failed"
        echo ""
        echo "Error details:"
        grep -E "(error|LLVM ERROR|panic|SIGSEGV)" "$log_file" | head -10
        
        # Save failure result
        echo "{
  \"test\": \"m68k-regression\",
  \"status\": \"failed\",
  \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",
  \"log_file\": \"$log_file\"
}" > "$LOG_DIR/m68k-regression-latest.json"
        
        return 1
    fi
}

# Main execution
if run_regression_test; then
    echo ""
    echo "=== Regression Test Passed ==="
    echo "The M68k scheduling model is working correctly."
    exit 0
else
    echo ""
    echo "=== Regression Test Failed ==="
    echo "Please check the logs at: $LOG_DIR"
    echo ""
    echo "This likely means:"
    echo "1. The M68k scheduling model needs updates"
    echo "2. LLVM changes broke M68k support"
    echo "3. Rust target specification needs adjustment"
    exit 1
fi