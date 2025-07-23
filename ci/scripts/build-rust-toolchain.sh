#!/bin/bash
# Build Rust toolchain with custom LLVM for M68k NeXTSTEP
# Last updated: 2025-07-22 10:45 AM

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

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if custom LLVM is built
if [ ! -d "$PROJECT_ROOT/toolchain/llvm-install" ]; then
    log_error "Custom LLVM not found. Please run ./ci/scripts/build-custom-llvm.sh first"
    exit 1
fi

# Set up environment for Rust build
export LLVM_CONFIG="$PROJECT_ROOT/toolchain/llvm-install/bin/llvm-config"
export CC="$PROJECT_ROOT/toolchain/llvm-install/bin/clang"
export CXX="$PROJECT_ROOT/toolchain/llvm-install/bin/clang++"
export AR="$PROJECT_ROOT/toolchain/llvm-install/bin/llvm-ar"
export RANLIB="$PROJECT_ROOT/toolchain/llvm-install/bin/llvm-ranlib"

# Rust source directory
RUST_SRC="$PROJECT_ROOT/rust-1.77"

# Build configuration
BUILD_DIR="$PROJECT_ROOT/toolchain/rust-build"
INSTALL_DIR="$PROJECT_ROOT/toolchain/rust-install"

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

log_info "Configuring Rust build with custom LLVM..."

# Configure Rust build
cat > config.toml << EOF
[llvm]
# Use our custom LLVM
link-shared = false
use-libcxx = false
static-libstdcpp = false
assertions = true
ccache = false
version-check = false
download-ci-llvm = false

[build]
# Basic build configuration
cargo = "cargo"
rustc = "rustc"
docs = false
compiler-docs = false
submodules = false
python = "python3"
locked-deps = true
vendor = false
extended = true
tools = ["cargo", "rustfmt"]
verbose = 2
sanitizers = false
profiler = false
cargo-native-static = false
low-priority = false

[rust]
# Rust compilation options
optimize = true
debug = false
codegen-units = 0
codegen-units-std = 1
debuginfo-level = 0
debuginfo-level-std = 0
debuginfo-level-tools = 0
debuginfo-level-tests = 0
rpath = false
verbose-tests = false
optimize-tests = false
codegen-tests = false
default-linker = "$PROJECT_ROOT/toolchain/llvm-install/bin/clang"
channel = "nightly"
description = "NeXTRust custom build"
remap-debuginfo = false
jemalloc = false

[target.x86_64-unknown-linux-gnu]
llvm-config = "$PROJECT_ROOT/toolchain/llvm-install/bin/llvm-config"
cc = "$PROJECT_ROOT/toolchain/llvm-install/bin/clang"
cxx = "$PROJECT_ROOT/toolchain/llvm-install/bin/clang++"
ar = "$PROJECT_ROOT/toolchain/llvm-install/bin/llvm-ar"
ranlib = "$PROJECT_ROOT/toolchain/llvm-install/bin/llvm-ranlib"

[target.m68k-unknown-linux-gnu]
llvm-config = "$PROJECT_ROOT/toolchain/llvm-install/bin/llvm-config"
cc = "$PROJECT_ROOT/toolchain/llvm-install/bin/clang"
cxx = "$PROJECT_ROOT/toolchain/llvm-install/bin/clang++"
ar = "$PROJECT_ROOT/toolchain/llvm-install/bin/llvm-ar"
ranlib = "$PROJECT_ROOT/toolchain/llvm-install/bin/llvm-ranlib"

[dist]
# Distribution options
src-tarball = false
missing-tools = true
compression-formats = ["gz"]

[install]
prefix = "$INSTALL_DIR"
sysconfdir = "etc"
EOF

log_info "Building Rust toolchain (this will take a while)..."
cd "$RUST_SRC"

# Apply the scheduler fix if not already applied
if ! grep -q "NoModel = 1" "$RUST_SRC/src/llvm-project/llvm/lib/Target/M68k/M68kSchedule.td"; then
    log_info "Applying M68k scheduler fix..."
    sed -i.bak 's/let CompleteModel = 0;/let CompleteModel = 0;\n  \/\/ Disable instruction scheduling to prevent crashes with incomplete model\n  let NoModel = 1;/' \
        "$RUST_SRC/src/llvm-project/llvm/lib/Target/M68k/M68kSchedule.td"
fi

# Build Rust
python3 x.py build --config "$BUILD_DIR/config.toml" --stage 1

log_info "Installing Rust toolchain..."
python3 x.py install --config "$BUILD_DIR/config.toml"

# Create wrapper script for our custom rustc
cat > "$INSTALL_DIR/bin/rustc-m68k" << 'EOF'
#!/bin/bash
# Wrapper for M68k Rust compilation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="$SCRIPT_DIR/../lib:$LD_LIBRARY_PATH"
exec "$SCRIPT_DIR/rustc" "$@"
EOF
chmod +x "$INSTALL_DIR/bin/rustc-m68k"

log_info "Rust toolchain built successfully!"
log_info "Toolchain installed at: $INSTALL_DIR"
log_info ""
log_info "To use this toolchain for M68k compilation:"
log_info "  export PATH=\"$INSTALL_DIR/bin:\$PATH\""
log_info "  rustc-m68k --target=m68k-next-nextstep ..."