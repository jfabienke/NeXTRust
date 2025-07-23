#!/bin/bash
# Run emulator tests for NeXTRust binaries
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCKER_IMAGE="nextrust/previous-emulator:latest"

# Configuration
ROM_PATH="${NEXTSTEP_ROM:-$HOME/NextStep/ROM/Rev_2.5_v66.BIN}"
DISK_PATH="${NEXTSTEP_DISK:-$HOME/NextStep/Disk/nextstep33.img}"
OS_VERSION="${NEXTSTEP_VERSION:-3.3}"
BINARY_PATH="${1:-}"
TIMEOUT="${EMULATOR_TIMEOUT:-60}"

# Support both NeXTSTEP 3.3 and OPENSTEP 4.2
case "$OS_VERSION" in
    "3.3")
        DISK_PATH="${NEXTSTEP_DISK:-$HOME/NextStep/Disk/nextstep33.img}"
        CONFIG_NAME="nextstep33"
        ;;
    "4.2")
        DISK_PATH="${OPENSTEP_DISK:-$HOME/NextStep/Disk/openstep42.img}"
        CONFIG_NAME="openstep42"
        ;;
    *)
        echo "Error: Unsupported OS version: $OS_VERSION" >&2
        echo "Supported versions: 3.3 (NeXTSTEP), 4.2 (OPENSTEP)" >&2
        exit 1
        ;;
esac

echo "=== NeXTRust Emulator Test Runner ==="

# Check prerequisites
if [[ -z "$BINARY_PATH" ]]; then
    echo "Usage: $0 <binary-path>" >&2
    echo "Example: $0 target/m68k-next-nextstep/debug/examples/hello-simple" >&2
    exit 1
fi

if [[ ! -f "$BINARY_PATH" ]]; then
    echo "Error: Binary not found: $BINARY_PATH" >&2
    exit 1
fi

if [[ ! -f "$ROM_PATH" ]]; then
    echo "Error: ROM not found: $ROM_PATH" >&2
    echo "Please set NEXTSTEP_ROM environment variable or place ROM at: $ROM_PATH" >&2
    echo "Required: Rev 2.5 v66 (68040) or Rev 1.x (68030)" >&2
    exit 1
fi

if [[ ! -f "$DISK_PATH" ]]; then
    echo "Error: Disk image not found: $DISK_PATH" >&2
    echo "Please set NEXTSTEP_DISK environment variable or place disk at: $DISK_PATH" >&2
    echo "You can create one with NeXTSTEP installer" >&2
    exit 1
fi

# Build Docker image if needed
if ! docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
    echo "Building Previous emulator Docker image..."
    docker build -t "$DOCKER_IMAGE" -f "$PROJECT_ROOT/tests/harness/docker/Dockerfile.previous-emulator" \
        "$PROJECT_ROOT/tests/harness/docker"
fi

# Prepare output directory
OUTPUT_DIR="$PROJECT_ROOT/test-results/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

# Run test in Docker
echo "Running test binary: $(basename "$BINARY_PATH")"
echo "OS Version: $OS_VERSION"
echo "ROM: $(basename "$ROM_PATH")"
echo "Disk: $(basename "$DISK_PATH")"
echo "Timeout: ${TIMEOUT}s"
echo ""

docker run --rm \
    -v "$BINARY_PATH:/test/binary:ro" \
    -v "$ROM_PATH:/test/rom.bin:ro" \
    -v "$DISK_PATH:/test/disk.img:ro" \
    -v "$OUTPUT_DIR:/output" \
    -e "NEXTSTEP_CONFIG=$CONFIG_NAME" \
    "$DOCKER_IMAGE" \
    /test/binary \
    --rom /test/rom.bin \
    --disk /test/disk.img \
    --timeout "$TIMEOUT" \
    --output /output

EXIT_CODE=$?

# Display results
echo ""
echo "=== Test Results ==="
if [[ -f "$OUTPUT_DIR/test.log" ]]; then
    echo "Output log: $OUTPUT_DIR/test.log"
    echo "--- Log Contents ---"
    cat "$OUTPUT_DIR/test.log"
    echo "--- End Log ---"
fi

# Check exit code
case $EXIT_CODE in
    0)
        echo " Test PASSED"
        ;;
    1)
        echo "L Test FAILED"
        ;;
    2)
        echo "�  Test TIMEOUT"
        ;;
    *)
        echo "S Test ERROR (exit code: $EXIT_CODE)"
        ;;
esac

exit $EXIT_CODE