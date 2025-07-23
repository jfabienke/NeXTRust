#!/bin/bash
# Setup and build core library for M68k using xargo
# Last updated: 2025-07-23 15:58 EEST

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check prerequisites
log_step "Checking prerequisites..."

if ! command -v xargo &> /dev/null; then
    log_error "xargo not found. Installing..."
    cargo install xargo || {
        log_error "Failed to install xargo"
        exit 1
    }
fi

if [ ! -d "$PROJECT_ROOT/toolchain/bin" ]; then
    log_error "Custom LLVM not found. Please run ./ci/scripts/build-custom-llvm.sh first"
    exit 1
fi

# Set up environment
log_step "Setting up environment..."
export LLVM_CONFIG="$PROJECT_ROOT/toolchain/bin/llvm-config"
export CC="$PROJECT_ROOT/toolchain/bin/clang"
export CXX="$PROJECT_ROOT/toolchain/bin/clang++"
export AR="$PROJECT_ROOT/toolchain/bin/llvm-ar"
export RANLIB="$PROJECT_ROOT/toolchain/bin/llvm-ranlib"
export RUSTFLAGS="-C llvm-args=-enable-machine-scheduler=false"

# Ensure we have rust-src
log_step "Installing rust-src component..."
rustup component add rust-src --toolchain nightly

# Create a workspace for xargo builds
XARGO_WORKSPACE="$PROJECT_ROOT/toolchain/xargo-workspace"
mkdir -p "$XARGO_WORKSPACE"
cd "$XARGO_WORKSPACE"

# Create a minimal Cargo.toml
log_step "Creating minimal project for xargo..."
cat > Cargo.toml << 'EOF'
[package]
name = "m68k-xargo-builder"
version = "0.1.0"
edition = "2021"

[dependencies]

[profile.release]
opt-level = "s"
lto = "thin"
panic = "abort"
codegen-units = 1
EOF

# Create src/lib.rs
mkdir -p src
cat > src/lib.rs << 'EOF'
#![no_std]
EOF

# Copy the target specification
log_step "Setting up target specification..."
mkdir -p targets
cp "$PROJECT_ROOT/targets/m68k-next-nextstep.json" targets/

# Create Xargo.toml with proper configuration
log_step "Creating Xargo.toml..."
cat > Xargo.toml << 'EOF'
[dependencies.core]
default-features = false

[dependencies.alloc]

[dependencies.compiler_builtins]
features = ["mem", "c"]
stage = 1
EOF

# Create .cargo/config.toml
mkdir -p .cargo
cat > .cargo/config.toml << EOF
[build]
target = "targets/m68k-next-nextstep.json"

[unstable]
build-std = ["core", "alloc", "compiler_builtins"]

[target.m68k-next-nextstep]
linker = "$PROJECT_ROOT/toolchain/bin/clang"

[env]
RUST_TARGET_PATH = "$XARGO_WORKSPACE/targets"
EOF

# Clear any existing xargo home
XARGO_HOME="$PROJECT_ROOT/toolchain/xargo-home"
rm -rf "$XARGO_HOME"
mkdir -p "$XARGO_HOME"

# Build with xargo
log_step "Building core library with xargo..."
export XARGO_HOME="$XARGO_HOME"
export RUST_TARGET_PATH="$XARGO_WORKSPACE/targets"

if xargo build --release --target m68k-next-nextstep --verbose 2>&1 | tee xargo-build.log; then
    log_info "✅ Xargo build succeeded!"
    
    # Find and display the sysroot
    SYSROOT=$(xargo --print-sysroot --target m68k-next-nextstep 2>/dev/null || echo "")
    if [ -n "$SYSROOT" ]; then
        log_info "Sysroot created at: $SYSROOT"
        log_info "Core library location: $SYSROOT/lib/rustlib/m68k-next-nextstep/lib/"
        
        # List the built libraries
        if [ -d "$SYSROOT/lib/rustlib/m68k-next-nextstep/lib" ]; then
            log_info "Built libraries:"
            ls -la "$SYSROOT/lib/rustlib/m68k-next-nextstep/lib/"
        fi
    fi
else
    log_error "❌ Xargo build failed!"
    log_error "Check xargo-build.log for details"
    
    # Try to extract meaningful error
    if grep -q "SIGSEGV" xargo-build.log; then
        log_error "LLVM segmentation fault detected - scheduler issue may persist"
    fi
    exit 1
fi

# Create a test program to verify the build
log_step "Creating test program..."
TEST_DIR="$XARGO_WORKSPACE/test"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

cat > test.rs << 'EOF'
#![no_std]
#![no_main]

use core::panic::PanicInfo;

#[no_mangle]
pub extern "C" fn _start() -> ! {
    // Simple test that uses core functionality
    let x: u32 = 42;
    let y: u32 = 13;
    let _z = x + y;
    
    loop {}
}

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}
EOF

# Try to compile the test program
log_step "Testing compilation with built core library..."
if rustc +nightly \
    --target "$XARGO_WORKSPACE/targets/m68k-next-nextstep.json" \
    --sysroot "$SYSROOT" \
    --crate-type bin \
    -C opt-level=s \
    -C panic=abort \
    -C llvm-args=-enable-machine-scheduler=false \
    -o test.o \
    test.rs 2>&1 | tee test-compile.log; then
    
    log_info "✅ Test compilation succeeded!"
    file test.o
    
    # Try to get symbol info
    if command -v "$PROJECT_ROOT/toolchain/bin/llvm-nm" &> /dev/null; then
        log_info "Symbols in test binary:"
        "$PROJECT_ROOT/toolchain/bin/llvm-nm" test.o | grep -E "(_start|panic)" || true
    fi
else
    log_error "❌ Test compilation failed!"
    cat test-compile.log
fi

log_info "Setup complete!"
log_info ""
log_info "To use this sysroot in your builds:"
log_info "  export XARGO_HOME=$XARGO_HOME"
log_info "  export RUST_TARGET_PATH=$XARGO_WORKSPACE/targets"
log_info "  xargo build --target m68k-next-nextstep"