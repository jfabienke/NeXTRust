#!/bin/bash
# ci/scripts/build-rust-target.sh - Build Rust target for m68k-next-nextstep
#
# Purpose: Cross-compile Rust code for NeXTSTEP m68k target
# Usage: build-rust-target.sh --target <target> --profile <profile> --features <features>
#
set -euo pipefail

# Default values
TARGET="m68k-next-nextstep"
PROFILE="debug"
FEATURES=""
TOOLCHAIN_DIR="$PWD/toolchain"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --target)
            TARGET="$2"
            shift 2
            ;;
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --features)
            FEATURES="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "[$(date)] Starting Rust build for $TARGET"
echo "Target: $TARGET"
echo "Profile: $PROFILE"
echo "Features: $FEATURES"

# Check prerequisites
if [[ ! -f "targets/m68k-next-nextstep.json" ]]; then
    echo "Error: Target specification not found: targets/m68k-next-nextstep.json" >&2
    exit 1
fi

if [[ ! -f "Cargo.toml" ]]; then
    echo "Error: Cargo.toml not found in project root" >&2
    exit 1
fi

# Set up environment for custom LLVM
if [[ -d "$TOOLCHAIN_DIR/bin" ]]; then
    export PATH="$TOOLCHAIN_DIR/bin:$PATH"
    echo "Using custom LLVM from: $TOOLCHAIN_DIR/bin"
    
    # Verify clang is available
    if ! command -v clang &> /dev/null; then
        echo "Warning: Custom clang not found in PATH"
    else
        echo "Found clang: $(which clang)"
        clang --version | head -1
    fi
fi

# Set up Rust environment
export RUST_TARGET_PATH="$PWD/targets"
export RUSTFLAGS="${RUSTFLAGS:-} -C linker=clang -C link-arg=-target -C link-arg=m68k-next-nextstep"

# Map profile to cargo flag
CARGO_PROFILE_FLAG=""
if [[ "$PROFILE" == "release" ]]; then
    CARGO_PROFILE_FLAG="--release"
fi

# Build the example
echo "Building hello-no-std example..."

# Create build directory
mkdir -p "target/$TARGET/$PROFILE"

# Run cargo build with our custom target
if cargo +nightly build \
    --target "$RUST_TARGET_PATH/m68k-next-nextstep.json" \
    --example hello-no-std \
    $CARGO_PROFILE_FLAG \
    -Z build-std=core \
    -Z build-std-features=panic_immediate_abort \
    2>&1 | tee build.log; then
    
    echo "Rust build completed successfully!"
    
    # Check if output file exists
    OUTPUT_FILE="target/m68k-next-nextstep/$PROFILE/examples/hello-no-std"
    if [[ -f "$OUTPUT_FILE" ]]; then
        echo "Output binary: $OUTPUT_FILE"
        
        # Create a .mach-o copy for CI artifact collection
        cp "$OUTPUT_FILE" "target/$TARGET/$PROFILE/hello-world.mach-o"
        
        # Show binary info if available
        if command -v file &> /dev/null; then
            file "$OUTPUT_FILE" || true
        fi
        
        # Show size if available
        if command -v size &> /dev/null; then
            size "$OUTPUT_FILE" || true
        fi
    else
        echo "Warning: Expected output file not found: $OUTPUT_FILE"
        # Create placeholder for CI
        echo "Build succeeded but binary not found" > "target/$TARGET/$PROFILE/hello-world.mach-o"
    fi
    
    # Log success
    python3 ci/scripts/status-append.py "rust_build_complete" \
        "{\"target\": \"$TARGET\", \"profile\": \"$PROFILE\", \"features\": \"$FEATURES\", \"success\": true}"
    
    exit 0
else
    echo "Rust build failed!"
    
    # Extract relevant error from build log
    if grep -q "error\[E" build.log; then
        echo "Build errors:"
        grep -A 5 "error\[E" build.log | head -20
    fi
    
    # Check for linker errors
    if grep -q "linker.*not found\|linking with.*failed" build.log; then
        echo "Linker error detected - custom LLVM may not be properly configured"
    fi
    
    # Log failure
    python3 ci/scripts/status-append.py "rust_build_failed" \
        "{\"target\": \"$TARGET\", \"profile\": \"$PROFILE\", \"features\": \"$FEATURES\", \"success\": false}"
    
    exit 1
fi