#!/bin/bash
# ci/scripts/build-rustc-phase1.sh - Phase 1: Build host-only rustc with custom LLVM
#
# Purpose: Build a host-only rustc that uses our custom LLVM but doesn't know about m68k target yet
# This avoids the chicken-and-egg problem where cargo tries to use m68k target before rustc supports it
#
# Last Updated: 2025-07-22 3:45 PM PST
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUST_BUILD_DIR="$PROJECT_ROOT/build/rust-phase1"
RUST_SRC_DIR="$PROJECT_ROOT/rust"
CUSTOM_LLVM_DIR="$PROJECT_ROOT/toolchain"
PHASE1_INSTALL="$PROJECT_ROOT/toolchain/rustc-phase1"

echo "=== Phase 1: Building Host-Only Rustc ==="
echo "This phase builds rustc for the host platform only"
echo "LLVM: $CUSTOM_LLVM_DIR"
echo "Install: $PHASE1_INSTALL"

# Check prerequisites
if [[ ! -f "$CUSTOM_LLVM_DIR/bin/llvm-config" ]]; then
    echo "Error: Custom LLVM not found. Run build-custom-llvm.sh first." >&2
    exit 1
fi

# Temporarily move .cargo/config.toml to avoid target conflicts
CARGO_CONFIG_BACKUP=""
if [[ -f "$PROJECT_ROOT/.cargo/config.toml" ]]; then
    echo "Temporarily moving .cargo/config.toml to avoid target conflicts..."
    CARGO_CONFIG_BACKUP="$PROJECT_ROOT/.cargo/config.toml.backup-$(date +%s)"
    mv "$PROJECT_ROOT/.cargo/config.toml" "$CARGO_CONFIG_BACKUP"
fi

# Cleanup function to restore config
cleanup() {
    if [[ -n "$CARGO_CONFIG_BACKUP" && -f "$CARGO_CONFIG_BACKUP" ]]; then
        echo "Restoring .cargo/config.toml..."
        mv "$CARGO_CONFIG_BACKUP" "$PROJECT_ROOT/.cargo/config.toml"
    fi
}
trap cleanup EXIT

# Clone or update rust repository
if [[ ! -d "$RUST_SRC_DIR" ]]; then
    echo "Cloning rust repository..."
    git clone https://github.com/rust-lang/rust.git "$RUST_SRC_DIR"
    cd "$RUST_SRC_DIR"
    # Use a stable version known to work
    git checkout 1.84.0
else
    cd "$RUST_SRC_DIR"
    # Clean any previous build artifacts
    if [[ -f "config.toml" ]]; then
        echo "Cleaning previous build configuration..."
        rm -f config.toml
    fi
fi

# Initialize submodules
echo "Initializing submodules..."
git submodule update --init --recursive

# Create phase 1 config - host only, no m68k
cat > config.toml << EOF
# Phase 1: Host-only build configuration
[llvm]
llvm-config = "$CUSTOM_LLVM_DIR/bin/llvm-config"
download-ci-llvm = false
link-shared = false
assertions = false
optimize = true

[build]
# Only build for host
build = "$(rustc -vV | grep host | cut -d' ' -f2)"
host = ["$(rustc -vV | grep host | cut -d' ' -f2)"]
target = ["$(rustc -vV | grep host | cut -d' ' -f2)"]
extended = true
tools = ["cargo", "rustfmt"]
verbose = 2
build-dir = "$RUST_BUILD_DIR"
# Use fewer codegen units to reduce memory usage
codegen-units = 1
# Don't build docs in phase 1
docs = false

[rust]
channel = "dev"
optimize = true
debuginfo-level = 0
codegen-units = 1
lto = "off"
# Don't enable any special features
deny-warnings = false

[dist]
compression-formats = ["gz"]
EOF

# Build phase 1
echo "Building rustc phase 1 (host-only)..."
echo "This will take 30-60 minutes..."

# Set up environment
export RUST_BACKTRACE=1
export CARGO_INCREMENTAL=0
unset CARGO_BUILD_TARGET
unset CARGO_TARGET_DIR

# Use python3
PYTHON_CMD="python3"
if ! command -v python3 &> /dev/null; then
    PYTHON_CMD="python"
fi

# Build stage 1 only (faster than full build)
time $PYTHON_CMD x.py build --stage 1 \
    --config config.toml \
    2>&1 | tee "$RUST_BUILD_DIR/phase1-build.log"

if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    echo "Error: Phase 1 build failed!" >&2
    echo "Check the build log: $RUST_BUILD_DIR/phase1-build.log" >&2
    exit 1
fi

# Install phase 1
echo "Installing phase 1 rustc to $PHASE1_INSTALL..."
$PYTHON_CMD x.py install --stage 1 --prefix="$PHASE1_INSTALL"

# Test phase 1
echo "Testing phase 1 rustc..."
"$PHASE1_INSTALL/bin/rustc" --version
"$PHASE1_INSTALL/bin/cargo" --version

# Create phase 1 marker
cat > "$PHASE1_INSTALL/phase1-complete.txt" << EOF
Phase 1 Build Complete
=====================
Date: $(date)
Host: $(rustc -vV | grep host | cut -d' ' -f2)
LLVM: $CUSTOM_LLVM_DIR

This is a host-only build without m68k support.
Use this to build phase 2 with m68k target.
EOF

echo "=== Phase 1 Complete ==="
echo "Rustc installed to: $PHASE1_INSTALL"
echo "Next step: Run build-rustc-phase2.sh"