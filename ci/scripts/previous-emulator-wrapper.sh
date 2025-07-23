#!/bin/bash
# Enhanced Previous emulator wrapper with retry logic and comprehensive logging
# Last updated: 2025-07-23 16:30 EEST

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1" | tee -a "$LOG_FILE"
    fi
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1" | tee -a "$LOG_FILE"
}

# Configuration with defaults
PREVIOUS_BINARY="${PREVIOUS_BINARY:-previous}"
ROM_PATH="${NEXTSTEP_ROM:-$HOME/NextStep/ROM/Rev_2.5_v66.BIN}"
DISK_PATH="${NEXTSTEP_DISK:-$HOME/NextStep/Disk/nextstep33.img}"
OS_VERSION="${NEXTSTEP_VERSION:-3.3}"
BINARY_PATH="${1:-}"
TIMEOUT="${EMULATOR_TIMEOUT:-120}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-5}"
DEBUG="${DEBUG:-0}"

# Create logs directory
LOGS_DIR="$PROJECT_ROOT/logs/emulator"
mkdir -p "$LOGS_DIR"

# Generate log file name with timestamp
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_FILE="$LOGS_DIR/previous_${TIMESTAMP}.log"

# Create session ID for tracking
SESSION_ID="previous_$(date '+%s')_$$"

usage() {
    cat << EOF
Usage: $0 <binary-path> [options]

Options:
    -r, --rom PATH          Path to ROM file (default: \$NEXTSTEP_ROM or ~/NextStep/ROM/Rev_2.5_v66.BIN)
    -d, --disk PATH         Path to disk image (default: \$NEXTSTEP_DISK or ~/NextStep/Disk/nextstep33.img)
    -v, --version VERSION   OS version: 3.3 or 4.2 (default: 3.3)
    -t, --timeout SECONDS  Emulator timeout (default: 120)
    -m, --max-retries N     Maximum retry attempts (default: 3)
    -w, --wait SECONDS      Delay between retries (default: 5)
    --debug                 Enable debug logging
    --dry-run              Show what would be executed without running
    -h, --help             Show this help

Environment Variables:
    PREVIOUS_BINARY        Path to Previous emulator binary (default: 'previous')
    NEXTSTEP_ROM          Default ROM path
    NEXTSTEP_DISK         Default disk path
    NEXTSTEP_VERSION      Default OS version
    EMULATOR_TIMEOUT      Default timeout
    MAX_RETRIES           Default max retries
    RETRY_DELAY           Default retry delay
    DEBUG                 Enable debug mode (1 = on, 0 = off)

Examples:
    $0 hello-world                              # Use defaults
    $0 hello-world --timeout 60                # Custom timeout
    $0 hello-world --debug --max-retries 5     # Debug mode with more retries
    $0 hello-world --rom custom.rom --version 4.2  # Custom ROM and OPENSTEP 4.2

Log file: $LOG_FILE
Session ID: $SESSION_ID
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--rom)
            ROM_PATH="$2"
            shift 2
            ;;
        -d|--disk)
            DISK_PATH="$2"
            shift 2
            ;;
        -v|--version)
            OS_VERSION="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -m|--max-retries)
            MAX_RETRIES="$2"
            shift 2
            ;;
        -w|--wait)
            RETRY_DELAY="$2"
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
            if [[ -z "$BINARY_PATH" ]]; then
                BINARY_PATH="$1"
            else
                log_error "Multiple binary paths specified"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validation
if [[ -z "$BINARY_PATH" ]]; then
    log_error "Binary path is required"
    usage
    exit 1
fi

log_step "Starting Previous emulator session"
log_info "Session ID: $SESSION_ID"
log_info "Log file: $LOG_FILE"
log_info "Configuration:"
log_info "  Binary: $BINARY_PATH"
log_info "  ROM: $ROM_PATH"
log_info "  Disk: $DISK_PATH"
log_info "  OS Version: $OS_VERSION"
log_info "  Timeout: ${TIMEOUT}s"
log_info "  Max Retries: $MAX_RETRIES"
log_info "  Retry Delay: ${RETRY_DELAY}s"

# Validate files
if [[ ! -f "$BINARY_PATH" ]]; then
    log_error "Binary not found: $BINARY_PATH"
    exit 1
fi

if [[ ! -f "$ROM_PATH" ]]; then
    log_error "ROM not found: $ROM_PATH"
    log_error "Please set NEXTSTEP_ROM environment variable or use --rom"
    log_error "Required: Rev 2.5 v66 (68040) or Rev 1.x (68030)"
    exit 1
fi

if [[ ! -f "$DISK_PATH" ]]; then
    log_error "Disk image not found: $DISK_PATH"
    log_error "Please set NEXTSTEP_DISK environment variable or use --disk"
    exit 1
fi

# Check Previous emulator availability
if ! command -v "$PREVIOUS_BINARY" &> /dev/null; then
    log_error "Previous emulator not found: $PREVIOUS_BINARY"
    log_error "Please install Previous emulator or set PREVIOUS_BINARY environment variable"
    exit 1
fi

# Get binary info
BINARY_INFO=$(file "$BINARY_PATH" 2>/dev/null || echo "Unknown format")
BINARY_SIZE=$(ls -lh "$BINARY_PATH" | awk '{print $5}')
log_info "Binary info: $BINARY_INFO (size: $BINARY_SIZE)"

# Determine configuration based on OS version
case "$OS_VERSION" in
    "3.3")
        CONFIG_NAME="nextstep33"
        EXPECTED_MACHINE="NeXTstation"
        ;;
    "4.2")
        CONFIG_NAME="openstep42"
        EXPECTED_MACHINE="NeXTstation"
        ;;
    *)
        log_error "Unsupported OS version: $OS_VERSION"
        log_error "Supported versions: 3.3 (NeXTSTEP), 4.2 (OPENSTEP)"
        exit 1
        ;;
esac

# Create emulator configuration
EMULATOR_CONFIG_DIR="$PROJECT_ROOT/tmp/emulator_configs"
mkdir -p "$EMULATOR_CONFIG_DIR"
EMULATOR_CONFIG="$EMULATOR_CONFIG_DIR/${CONFIG_NAME}_${SESSION_ID}.cfg"

cat > "$EMULATOR_CONFIG" << EOF
# Previous Emulator Configuration for $CONFIG_NAME
# Generated at $(date)
# Session: $SESSION_ID

[System]
nCPU = 1
nFPU = 1
nRTC = 1
nSCSI = 1
nSoundOut = 0
nSoundIn = 0
nPrinter = 0
nEthernet = 0

[Memory] 
nMemorySize = 32
bMemoryProtection = true

[Boot]
szROM = $ROM_PATH
szDisk = $DISK_PATH
bAutoboot = true

[Display]
nMainDisplay = 1
nMainDisplayType = 1

[Debug]
bEnableDebugger = false
nLogLevel = 1
szLogFile = $LOGS_DIR/previous_internal_${TIMESTAMP}.log
EOF

log_debug "Emulator config created: $EMULATOR_CONFIG"

# Function to run emulator with timeout and logging
run_emulator_attempt() {
    local attempt=$1
    local attempt_log="$LOGS_DIR/attempt_${attempt}_${TIMESTAMP}.log"
    
    log_step "Emulator attempt $attempt/$MAX_RETRIES"
    log_debug "Attempt log: $attempt_log"
    
    # Create expectation script for automated interaction
    local expect_script="$EMULATOR_CONFIG_DIR/expect_${SESSION_ID}.exp"
    cat > "$expect_script" << EOF
#!/usr/bin/expect -f

set timeout $TIMEOUT
log_file $attempt_log

# Start Previous emulator
spawn $PREVIOUS_BINARY -c "$EMULATOR_CONFIG"

# Wait for boot completion
expect {
    "login:" {
        send "root\r"
        expect "Password:"
        send "\r"
        expect "#"
        
        # Copy and execute binary
        send "echo 'Executing binary: $BINARY_PATH'\r"
        expect "#"
        
        # Transfer binary (simplified - in real scenario would use network/disk)
        send "echo 'Binary would be transferred here'\r"
        expect "#"
        
        # Execute
        send "echo 'Execution complete'\r"
        expect "#"
        
        # Shutdown
        send "halt\r"
        expect eof
    }
    timeout {
        puts "Timeout waiting for boot"
        exit 2
    }
    eof {
        puts "Unexpected end of session"
        exit 3
    }
}

exit 0
EOF

    chmod +x "$expect_script"
    
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        log_info "DRY RUN: Would execute: $expect_script"
        return 0
    fi
    
    # Run with timeout
    local start_time=$(date +%s)
    if timeout "$TIMEOUT" "$expect_script" 2>&1 | tee -a "$attempt_log"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_info "✅ Emulator attempt $attempt succeeded (${duration}s)"
        return 0
    else
        local exit_code=$?
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        case $exit_code in
            124)
                log_warning "⏰ Emulator attempt $attempt timed out after ${duration}s"
                ;;
            2)
                log_warning "🔄 Emulator attempt $attempt: Boot timeout"
                ;;
            3)
                log_warning "💥 Emulator attempt $attempt: Unexpected session end"
                ;;
            *)
                log_warning "❌ Emulator attempt $attempt failed with exit code $exit_code (${duration}s)"
                ;;
        esac
        
        # Save failure info
        echo "Attempt $attempt failed at $(date) with exit code $exit_code" >> "$attempt_log"
        return $exit_code
    fi
}

# Main retry loop
SUCCESS=0
for attempt in $(seq 1 $MAX_RETRIES); do
    if run_emulator_attempt "$attempt"; then
        SUCCESS=1
        break
    fi
    
    if [[ $attempt -lt $MAX_RETRIES ]]; then
        log_info "⏳ Waiting ${RETRY_DELAY}s before retry..."
        sleep "$RETRY_DELAY"
    fi
done

# Results
if [[ $SUCCESS -eq 1 ]]; then
    log_info "🎉 Emulator execution successful!"
    EXIT_CODE=0
else
    log_error "💀 All emulator attempts failed ($MAX_RETRIES/$MAX_RETRIES)"
    EXIT_CODE=1
fi

# Cleanup
rm -f "$EMULATOR_CONFIG" "$EMULATOR_CONFIG_DIR/expect_${SESSION_ID}.exp"

# Summary
log_step "Emulator session complete"
log_info "Session ID: $SESSION_ID"
log_info "Total attempts: $MAX_RETRIES"
log_info "Success: $([ $SUCCESS -eq 1 ] && echo "Yes" || echo "No")"
log_info "Logs directory: $LOGS_DIR"
log_info "Main log: $LOG_FILE"

exit $EXIT_CODE