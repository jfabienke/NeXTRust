#!/bin/bash
# Build libcore manually for M68k NeXTSTEP target
# Last updated: 2025-07-22 10:50 AM

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Check prerequisites
if [ ! -d "$PROJECT_ROOT/toolchain/llvm-install" ]; then
    log_error "Custom LLVM not found. Please run ./ci/scripts/build-custom-llvm.sh first"
    exit 1
fi

# Set up environment
export LLVM_CONFIG="$PROJECT_ROOT/toolchain/llvm-install/bin/llvm-config"
export CC="$PROJECT_ROOT/toolchain/llvm-install/bin/clang"
export CXX="$PROJECT_ROOT/toolchain/llvm-install/bin/clang++"
export AR="$PROJECT_ROOT/toolchain/llvm-install/bin/llvm-ar"
export RANLIB="$PROJECT_ROOT/toolchain/llvm-install/bin/llvm-ranlib"

# Create a minimal Rust project to build core
CORE_BUILD_DIR="$PROJECT_ROOT/toolchain/core-build"
mkdir -p "$CORE_BUILD_DIR"
cd "$CORE_BUILD_DIR"

log_info "Setting up minimal project for core build..."

# Create Cargo.toml
cat > Cargo.toml << 'EOF'
[package]
name = "m68k-core-builder"
version = "0.1.0"
edition = "2021"

[dependencies]

[profile.release]
opt-level = "s"
lto = true
panic = "abort"
EOF

# Create minimal src/lib.rs
mkdir -p src
cat > src/lib.rs << 'EOF'
#![no_std]
#![no_main]

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
EOF

# Create .cargo/config.toml
mkdir -p .cargo
cat > .cargo/config.toml << EOF
[build]
target = "m68k-unknown-linux-gnu"

[target.m68k-unknown-linux-gnu]
linker = "$PROJECT_ROOT/toolchain/llvm-install/bin/clang"
rustflags = [
    "-C", "opt-level=s",
    "-C", "panic=abort",
    "-C", "relocation-model=static",
    "-C", "code-model=small",
    "-C", "target-cpu=generic",
    "-C", "llvm-args=-enable-machine-scheduler=false",
    "-Z", "emit-stack-sizes"
]

[unstable]
build-std = ["core", "compiler_builtins", "alloc"]
build-std-features = ["compiler-builtins-mem"]
EOF

log_info "Building core library for M68k..."

# First, try with the nightly toolchain
if command -v rustup &> /dev/null; then
    log_info "Using rustup nightly toolchain..."
    rustup toolchain install nightly
    rustup component add rust-src --toolchain nightly
    
    # Build with explicit LLVM override
    RUSTFLAGS="-C llvm-args=-enable-machine-scheduler=false" \
    cargo +nightly build --release -Z build-std=core,alloc \
        --target m68k-unknown-linux-gnu 2>&1 | tee build.log || {
        log_error "Build failed. Checking error..."
        if grep -q "SIGSEGV" build.log; then
            log_error "Still getting SIGSEGV. Need to rebuild LLVM with scheduler fix."
        fi
    }
fi

# Alternative: Use xargo if available
if command -v xargo &> /dev/null; then
    log_info "Trying xargo as alternative..."
    cat > Xargo.toml << 'EOF'
[dependencies.core]
[dependencies.alloc]
[dependencies.compiler_builtins]
features = ["mem"]
stage = 0
EOF
    
    xargo build --release --target m68k-unknown-linux-gnu || {
        log_error "Xargo build failed"
    }
fi

log_info "Core build attempt completed. Check build.log for details."