#!/bin/bash
# Build core library for M68k using cargo +nightly -Z build-std
# Last updated: 2025-07-23 16:05 EEST

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

# Ensure we have rust-src
log_step "Installing rust-src component..."
rustup component add rust-src --toolchain nightly

# Create a test project for building core
BUILD_DIR="$PROJECT_ROOT/toolchain/core-build-test"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Create a minimal project
log_step "Creating test project..."
cat > Cargo.toml << 'EOF'
[package]
name = "m68k-core-test"
version = "0.1.0"
edition = "2021"

[dependencies]

[profile.release]
opt-level = "s"
lto = false
panic = "abort"
codegen-units = 1
EOF

# Create src/main.rs
mkdir -p src
cat > src/main.rs << 'EOF'
#![no_std]
#![no_main]

use core::panic::PanicInfo;

#[no_mangle]
pub extern "C" fn _start() -> ! {
    // Simple test
    let x: u32 = 42;
    let y: u32 = 13;
    let _z = x.wrapping_add(y);
    
    loop {}
}

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}

// Minimal compiler builtins to avoid linking errors
#[no_mangle]
pub extern "C" fn __aeabi_unwind_cpp_pr0() {}

#[no_mangle]
pub extern "C" fn __aeabi_unwind_cpp_pr1() {}
EOF

# Copy the target specification
cp "$PROJECT_ROOT/targets/m68k-next-nextstep.json" .

# Create .cargo/config.toml with proper settings
mkdir -p .cargo
cat > .cargo/config.toml << EOF
[build]
target = "m68k-next-nextstep.json"

[target.m68k-next-nextstep]
linker = "$PROJECT_ROOT/toolchain/bin/clang"
rustflags = [
    "-C", "link-arg=-nostdlib",
    "-C", "link-arg=-static",
    "-C", "opt-level=s",
    "-C", "panic=abort",
    "-C", "relocation-model=static",
    "-C", "code-model=small"
]
EOF

# Build with cargo +nightly -Z build-std
log_step "Building core library with cargo +nightly..."
if RUST_TARGET_PATH="$BUILD_DIR" \
   cargo +nightly build \
   --release \
   --target m68k-next-nextstep.json \
   -Z build-std=core,alloc,compiler_builtins \
   -Z build-std-features=compiler-builtins-mem \
   --verbose 2>&1 | tee build.log; then
    
    log_info "✅ Build succeeded!"
    
    # Check the output
    if [ -f "target/m68k-next-nextstep/release/m68k-core-test" ]; then
        log_info "Binary created successfully!"
        file target/m68k-next-nextstep/release/m68k-core-test
        
        # Check symbols
        if [ -x "$PROJECT_ROOT/toolchain/bin/llvm-nm" ]; then
            log_info "Symbols in binary:"
            "$PROJECT_ROOT/toolchain/bin/llvm-nm" target/m68k-next-nextstep/release/m68k-core-test | grep -E "(_start|panic)" || true
        fi
    fi
    
    # Check for core library
    CORE_LIB="target/m68k-next-nextstep/release/deps/libcore-*.rlib"
    if ls $CORE_LIB 1> /dev/null 2>&1; then
        log_info "Core library built:"
        ls -la $CORE_LIB
    fi
else
    log_error "❌ Build failed!"
    
    # Try to extract meaningful error
    if grep -q "SIGSEGV" build.log; then
        log_error "LLVM segmentation fault detected"
        log_error "The M68k scheduling issue is still present"
    elif grep -q "cannot find" build.log; then
        log_error "Missing dependencies detected"
    fi
    
    log_info "Last 50 lines of build log:"
    tail -50 build.log
    exit 1
fi

log_info ""
log_info "Build complete!"
log_info "To use this in other projects, set:"
log_info "  export RUST_TARGET_PATH=$BUILD_DIR"
log_info "  cargo +nightly build --target m68k-next-nextstep.json -Z build-std=core,alloc"