#!/bin/bash
# Automated emulator test harness for NeXTRust
# Discovers and runs test cases, generates reports
# Last updated: 2025-07-23 16:35 EEST

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

log_test() {
    echo -e "${MAGENTA}[TEST]${NC} $1"
}

# Configuration
TEST_DIR="${TEST_DIR:-$PROJECT_ROOT/tests}"
RESULTS_DIR="${RESULTS_DIR:-$PROJECT_ROOT/test-results}"
EMULATOR_WRAPPER="$SCRIPT_DIR/previous-emulator-wrapper.sh"
PARALLEL_JOBS="${PARALLEL_JOBS:-1}"
FILTER_PATTERN="${FILTER_PATTERN:-*}"
DEBUG="${DEBUG:-0}"
DRY_RUN="${DRY_RUN:-0}"

# Generate test session ID
SESSION_ID="harness_$(date '+%Y%m%d_%H%M%S')_$$"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

usage() {
    cat << EOF
Usage: $0 [options]

Options:
    -t, --test-dir PATH     Test directory (default: $TEST_DIR)
    -r, --results-dir PATH  Results directory (default: $RESULTS_DIR)
    -j, --jobs N           Number of parallel jobs (default: $PARALLEL_JOBS)
    -f, --filter PATTERN   Test filter pattern (default: $FILTER_PATTERN)
    --debug                Enable debug logging
    --dry-run              Show what would be executed without running
    --list-tests           List discovered tests and exit
    --clean-results        Clean old results before running
    -h, --help             Show this help

Test Discovery:
    The harness discovers tests in the following ways:
    1. Executable files in test directories
    2. Test configuration files (*.test.json)
    3. Built binaries matching test patterns

Test Configuration File Format (optional):
    {
        "name": "Test Name",
        "binary": "path/to/binary",
        "timeout": 120,
        "expected_exit_code": 0,
        "description": "Test description",
        "tags": ["tag1", "tag2"],
        "requirements": {
            "rom": "Rev_2.5_v66.BIN",
            "disk": "nextstep33.img",
            "memory": "32MB"
        }
    }

Environment Variables:
    TEST_DIR              Test directory path
    RESULTS_DIR          Results directory path
    PARALLEL_JOBS        Number of parallel test jobs
    FILTER_PATTERN       Test filter pattern
    DEBUG                Enable debug mode (1/0)
    DRY_RUN              Dry run mode (1/0)

Examples:
    $0                                  # Run all tests
    $0 --filter "*hello*"              # Run tests matching pattern
    $0 --jobs 4 --debug                # Parallel tests with debug
    $0 --list-tests                     # List available tests
    $0 --clean-results --filter basic  # Clean and run basic tests

Session ID: $SESSION_ID
EOF
}

# Parse command line arguments
LIST_TESTS=0
CLEAN_RESULTS=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--test-dir)
            TEST_DIR="$2"
            shift 2
            ;;
        -r|--results-dir)
            RESULTS_DIR="$2"
            shift 2
            ;;
        -j|--jobs)
            PARALLEL_JOBS="$2"
            shift 2
            ;;
        -f|--filter)
            FILTER_PATTERN="$2"
            shift 2
            ;;
        --debug)
            DEBUG=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --list-tests)
            LIST_TESTS=1
            shift
            ;;
        --clean-results)
            CLEAN_RESULTS=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            log_error "Unexpected argument: $1"
            usage
            exit 1
            ;;
    esac
done

log_step "Starting emulator test harness"
log_info "Session ID: $SESSION_ID"
log_info "Test directory: $TEST_DIR"
log_info "Results directory: $RESULTS_DIR"
log_info "Filter pattern: $FILTER_PATTERN"
log_info "Parallel jobs: $PARALLEL_JOBS"

# Clean results if requested
if [[ $CLEAN_RESULTS -eq 1 ]]; then
    log_step "Cleaning old results"
    rm -rf "$RESULTS_DIR"
fi

# Create results directory
mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/test-results-${TIMESTAMP}.json"
SUMMARY_FILE="$RESULTS_DIR/test-summary-${TIMESTAMP}.txt"

# Initialize results file
cat > "$RESULTS_FILE" << EOF
{
    "session_id": "$SESSION_ID",
    "timestamp": "$(date -Iseconds)",
    "configuration": {
        "test_dir": "$TEST_DIR",
        "filter_pattern": "$FILTER_PATTERN",
        "parallel_jobs": $PARALLEL_JOBS,
        "debug": $DEBUG,
        "dry_run": $DRY_RUN
    },
    "tests": []
}
EOF

# Test discovery function
discover_tests() {
    local tests=()
    
    # Method 1: Find executable files in test directories
    if [[ -d "$TEST_DIR" ]]; then
        while IFS= read -r -d '' binary; do
            if [[ -x "$binary" && "$binary" == *"$FILTER_PATTERN"* ]]; then
                tests+=("$binary")
            fi
        done < <(find "$TEST_DIR" -type f -perm -u+x -print0 2>/dev/null || true)
    fi
    
    # Method 2: Find test configuration files
    if [[ -d "$TEST_DIR" ]]; then
        while IFS= read -r -d '' config; do
            if [[ "$config" == *"$FILTER_PATTERN"* ]]; then
                tests+=("$config")
            fi
        done < <(find "$TEST_DIR" -name "*.test.json" -print0 2>/dev/null || true)
    fi
    
    # Method 3: Look for built examples and binaries
    local search_paths=(
        "$PROJECT_ROOT/target/*/debug/examples/*"
        "$PROJECT_ROOT/target/*/release/examples/*"
        "$PROJECT_ROOT/target/*/debug/*"
        "$PROJECT_ROOT/target/*/release/*"
        "$PROJECT_ROOT/toolchain/*/test/*"
        "$PROJECT_ROOT/build/*/examples/*"
    )
    
    for pattern in "${search_paths[@]}"; do
        for binary in $pattern; do
            if [[ -f "$binary" && -x "$binary" && "$binary" == *"$FILTER_PATTERN"* ]]; then
                # Skip if already added
                if [[ ! " ${tests[*]} " =~ " $binary " ]]; then
                    tests+=("$binary")
                fi
            fi
        done 2>/dev/null || true
    done
    
    # Remove duplicates and sort
    if [[ ${#tests[@]} -gt 0 ]]; then
        printf '%s\n' "${tests[@]}" | sort -u
    fi
}

# Parse test configuration
parse_test_config() {
    local test_path="$1"
    
    if [[ "$test_path" == *.test.json ]]; then
        # JSON configuration file
        if command -v jq &> /dev/null; then
            echo "config:$test_path"
        else
            log_warning "jq not found, skipping JSON test config: $test_path"
            return 1
        fi
    else
        # Executable binary
        echo "binary:$test_path"
    fi
}

# Run single test
run_single_test() {
    local test_spec="$1"
    local test_index="$2"
    
    local test_type="${test_spec%%:*}"
    local test_path="${test_spec#*:}"
    local test_name="$(basename "$test_path")"
    
    log_test "Running test $test_index: $test_name"
    
    local test_start=$(date +%s)
    local test_results_dir="$RESULTS_DIR/test_${test_index}_${test_name}"
    mkdir -p "$test_results_dir"
    
    # Test metadata
    local binary_path=""
    local timeout=120
    local expected_exit_code=0
    local description=""
    local tags=()
    
    if [[ "$test_type" == "config" ]]; then
        # Parse JSON configuration
        if command -v jq &> /dev/null; then
            binary_path=$(jq -r '.binary // empty' "$test_path" 2>/dev/null || echo "")
            timeout=$(jq -r '.timeout // 120' "$test_path" 2>/dev/null || echo "120")
            expected_exit_code=$(jq -r '.expected_exit_code // 0' "$test_path" 2>/dev/null || echo "0")
            description=$(jq -r '.description // ""' "$test_path" 2>/dev/null || echo "")
            
            # Resolve relative binary path
            if [[ -n "$binary_path" && "$binary_path" != /* ]]; then
                binary_path="$(dirname "$test_path")/$binary_path"
            fi
        fi
    else
        # Direct binary
        binary_path="$test_path"
    fi
    
    # Validate binary exists
    if [[ ! -f "$binary_path" ]]; then
        log_error "Test binary not found: $binary_path"
        return 1
    fi
    
    # Run the test
    local test_exit_code=0
    local test_log="$test_results_dir/emulator.log"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY RUN: Would run $EMULATOR_WRAPPER \"$binary_path\""
        test_exit_code=0
    else
        if DEBUG="$DEBUG" "$EMULATOR_WRAPPER" "$binary_path" > "$test_log" 2>&1; then
            test_exit_code=0
        else
            test_exit_code=$?
        fi
    fi
    
    local test_end=$(date +%s)
    local test_duration=$((test_end - test_start))
    
    # Determine test result
    local test_status="FAIL"
    if [[ $test_exit_code -eq $expected_exit_code ]]; then
        test_status="PASS"
        log_info "✅ Test $test_index ($test_name): PASSED (${test_duration}s)"
    else
        log_error "❌ Test $test_index ($test_name): FAILED (${test_duration}s, exit: $test_exit_code, expected: $expected_exit_code)"
    fi
    
    # Create test result JSON
    local test_result_json="$test_results_dir/result.json"
    cat > "$test_result_json" << EOF
{
    "test_index": $test_index,
    "test_name": "$test_name",
    "test_path": "$test_path",
    "binary_path": "$binary_path",
    "test_type": "$test_type",
    "status": "$test_status",
    "exit_code": $test_exit_code,
    "expected_exit_code": $expected_exit_code,
    "duration_seconds": $test_duration,
    "timestamp": $(date +%s),
    "description": "$description",
    "log_file": "$test_log"
}
EOF
    
    echo "$test_result_json"
}

# Discover tests
log_step "Discovering tests"
DISCOVERED_TESTS=()
while IFS= read -r test; do
    DISCOVERED_TESTS+=("$test")
done < <(discover_tests)

if [[ ${#DISCOVERED_TESTS[@]} -eq 0 ]]; then
    log_warning "No tests found matching pattern: $FILTER_PATTERN"
    log_info "Search locations:"
    log_info "  - Test directory: $TEST_DIR"
    log_info "  - Built examples and binaries"
    exit 0
fi

log_info "Found ${#DISCOVERED_TESTS[@]} test(s)"

# Parse test specifications
TESTS_TO_RUN=()
for test_path in "${DISCOVERED_TESTS[@]}"; do
    if test_spec=$(parse_test_config "$test_path"); then
        TESTS_TO_RUN+=("$test_spec")
    fi
done

log_info "Prepared ${#TESTS_TO_RUN[@]} test(s) for execution"

# List tests if requested
if [[ $LIST_TESTS -eq 1 ]]; then
    log_step "Available tests:"
    for i in "${!TESTS_TO_RUN[@]}"; do
        local test_spec="${TESTS_TO_RUN[$i]}"
        local test_type="${test_spec%%:*}"
        local test_path="${test_spec#*:}"
        local test_name="$(basename "$test_path")"
        echo "  $((i+1)). $test_name ($test_type: $test_path)"
    done
    exit 0
fi

# Run tests
log_step "Running ${#TESTS_TO_RUN[@]} test(s) with $PARALLEL_JOBS parallel job(s)"

START_TIME=$(date +%s)
PASSED_TESTS=0
FAILED_TESTS=0

# Function to process test results
process_test_result() {
    local result_file="$1"
    if [[ -f "$result_file" ]]; then
        local status=$(jq -r '.status' "$result_file" 2>/dev/null || echo "UNKNOWN")
        if [[ "$status" == "PASS" ]]; then
            ((PASSED_TESTS++))
        else
            ((FAILED_TESTS++))
        fi
        
        # Add to combined results
        local test_json=$(cat "$result_file")
        # Note: This is a simplified approach - in practice would need proper JSON merging
        echo "  $test_json," >> "$RESULTS_FILE.tmp"
    fi
}

# Simple sequential execution (can be enhanced for parallel)
echo '{"tests":[' > "$RESULTS_FILE.tmp"
for i in "${!TESTS_TO_RUN[@]}"; do
    local test_spec="${TESTS_TO_RUN[$i]}"
    if result_file=$(run_single_test "$test_spec" "$((i+1))"); then
        process_test_result "$result_file"
    fi
done

# Finalize results file
echo ']}' >> "$RESULTS_FILE.tmp"
# Clean up trailing comma and merge with header
head -n -1 "$RESULTS_FILE" > "$RESULTS_FILE.new"
sed '$ s/,$//' "$RESULTS_FILE.tmp" | tail -n +2 >> "$RESULTS_FILE.new"
mv "$RESULTS_FILE.new" "$RESULTS_FILE"
rm -f "$RESULTS_FILE.tmp"

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

# Generate summary
log_step "Test execution complete"

cat > "$SUMMARY_FILE" << EOF
NeXTRust Emulator Test Harness Summary
======================================

Session ID: $SESSION_ID
Timestamp: $(date)
Duration: ${TOTAL_DURATION}s

Configuration:
- Test Directory: $TEST_DIR
- Filter Pattern: $FILTER_PATTERN
- Parallel Jobs: $PARALLEL_JOBS
- Debug Mode: $DEBUG
- Dry Run: $DRY_RUN

Results:
- Total Tests: ${#TESTS_TO_RUN[@]}
- Passed: $PASSED_TESTS
- Failed: $FAILED_TESTS
- Success Rate: $(( PASSED_TESTS * 100 / ${#TESTS_TO_RUN[@]} ))%

Files:
- Detailed Results: $RESULTS_FILE
- Summary: $SUMMARY_FILE
- Individual Test Results: $RESULTS_DIR/test_*/
EOF

# Display summary
cat "$SUMMARY_FILE"

# Exit with appropriate code
if [[ $FAILED_TESTS -eq 0 ]]; then
    log_info "🎉 All tests passed!"
    exit 0
else
    log_error "💀 Some tests failed ($FAILED_TESTS/${#TESTS_TO_RUN[@]})"
    exit 1
fi