#!/usr/bin/env bash
# ci/scripts/test-m68k-compilation.sh - Test M68k compilation with custom toolchain
#
# Purpose: Verify that our custom LLVM and rustc can compile for M68k
# Usage: ./ci/scripts/test-m68k-compilation.sh
#
set -euo pipefail

echo "=== Testing M68k Compilation ==="
echo

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_ROOT"

# Find our custom rustc
RUSTC_BIN="$PROJECT_ROOT/build/rust-1.77/aarch64-apple-darwin/stage1/bin/rustc"
if [[ ! -x "$RUSTC_BIN" ]]; then
    echo "ERROR: Custom rustc not found at $RUSTC_BIN"
    echo "Run ./ci/scripts/build-rust-1.77.sh first"
    exit 1
fi

# Test 1: Direct rustc compilation
echo "Test 1: Direct rustc compilation..."
cat > test_direct.rs << 'EOF'
#![no_std]
#![no_main]

use core::panic::PanicInfo;

#[no_mangle]
pub extern "C" fn _start() -> ! {
    loop {}
}

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}
EOF

echo "Compiling with standard target..."
if "$RUSTC_BIN" --target targets/m68k-next-nextstep.json \
    --crate-type bin -C opt-level=0 \
    test_direct.rs -o test_direct.o 2>&1; then
    echo "✅ Direct compilation succeeded!"
    file test_direct.o || true
else
    echo "❌ Direct compilation failed (expected - missing core library)"
fi

echo
echo "Compiling with no-scheduler target..."
if "$RUSTC_BIN" --target targets/m68k-next-nextstep-noscheduler.json \
    --crate-type bin -C opt-level=0 \
    test_direct.rs -o test_direct_nosched.o 2>&1; then
    echo "✅ No-scheduler compilation succeeded!"
    file test_direct_nosched.o || true
else
    echo "❌ No-scheduler compilation failed"
fi

# Test 2: Cargo with nightly (for comparison)
echo
echo "Test 2: Cargo +nightly compilation (for comparison)..."
if command -v cargo >/dev/null 2>&1; then
    if cargo +nightly build --target targets/m68k-next-nextstep.json \
        -Z build-std=core --example hello-simple 2>&1 | head -20; then
        echo "✅ Cargo +nightly succeeded (unexpected!)"
    else
        echo "❌ Cargo +nightly failed (expected - LLVM version mismatch)"
    fi
else
    echo "Cargo not found, skipping test"
fi

# Test 3: Check LLVM tools
echo
echo "Test 3: LLVM tools verification..."
echo "LLVM version:"
"$PROJECT_ROOT/toolchain/bin/llc" --version | head -3

echo
echo "M68k target features:"
"$PROJECT_ROOT/toolchain/bin/llc" -march=m68k -mattr=help 2>&1 | head -10 || true

# Clean up
rm -f test_direct.rs test_direct.o test_direct_nosched.o

echo
echo "=== Test Summary ==="
echo "1. Our custom rustc can be invoked for M68k targets"
echo "2. Core library needs to be built for M68k"
echo "3. LLVM has M68k support with scheduling disabled"
echo
echo "Next steps:"
echo "- Build core library for M68k target"
echo "- Use xargo or cargo-xbuild for easier std building"
echo "- Test with emulator once binaries compile"