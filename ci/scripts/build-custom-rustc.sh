#!/bin/bash
# ci/scripts/build-custom-rustc.sh - Build custom rustc with our LLVM patches
#
# Purpose: Build a custom Rust compiler that uses our patched LLVM with M68k scheduling
# Usage: build-custom-rustc.sh [--stage1|--stage2] [--release]
#
# Requirements:
# - 16GB+ RAM (use swap if needed)  
# - 50GB+ free disk space
# - Our custom LLVM already built in toolchain/
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUST_BUILD_DIR="$PROJECT_ROOT/build/rust"
RUST_SRC_DIR="$PROJECT_ROOT/rust"
CUSTOM_LLVM_DIR="$PROJECT_ROOT/toolchain"
RUSTC_VERSION="1.84.0"  # Use stable version for reproducibility

# Parse arguments
STAGE="2"
BUILD_TYPE="debug"
while [[ $# -gt 0 ]]; do
    case $1 in
        --stage1)
            STAGE="1"
            shift
            ;;
        --stage2)
            STAGE="2"
            shift
            ;;
        --release)
            BUILD_TYPE="release"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "=== Building Custom Rustc with M68k Support ==="
echo "Stage: $STAGE"
echo "Build type: $BUILD_TYPE"
echo "LLVM: $CUSTOM_LLVM_DIR"

# Check prerequisites
if [[ ! -f "$CUSTOM_LLVM_DIR/bin/llvm-config" ]]; then
    echo "Error: Custom LLVM not found. Run build-custom-llvm.sh first." >&2
    exit 1
fi

# Check system resources
AVAILABLE_MEM=$(sysctl -n hw.memsize 2>/dev/null || grep MemTotal /proc/meminfo | awk '{print $2*1024}' 2>/dev/null || echo 0)
AVAILABLE_MEM_GB=$((AVAILABLE_MEM / 1024 / 1024 / 1024))
if [[ $AVAILABLE_MEM_GB -lt 8 ]]; then
    echo "Warning: Less than 8GB RAM available. Build may fail."
    echo "Consider using swap or reducing codegen-units."
fi

# Clone or update rust repository
if [[ ! -d "$RUST_SRC_DIR" ]]; then
    echo "Cloning rust repository (this may take a while)..."
    git clone https://github.com/rust-lang/rust.git "$RUST_SRC_DIR"
    cd "$RUST_SRC_DIR"
    git checkout "$RUSTC_VERSION"
else
    echo "Updating rust repository..."
    cd "$RUST_SRC_DIR"
    git fetch origin
    git checkout "$RUSTC_VERSION"
fi

# Initialize submodules
echo "Initializing submodules..."
git submodule update --init --recursive

# Create config.toml
echo "Creating build configuration..."
cat > config.toml << EOF
# Rust build configuration for NeXTRust

[llvm]
# Use our custom LLVM with M68k scheduling patches
llvm-config = "$CUSTOM_LLVM_DIR/bin/llvm-config"
# Don't download CI LLVM
download-ci-llvm = false
# Link statically for easier distribution
link-shared = false
# Enable assertions in debug builds
assertions = $(if [[ "$BUILD_TYPE" == "debug" ]]; then echo "true"; else echo "false"; fi)
# Optimize LLVM in release builds
optimize = $(if [[ "$BUILD_TYPE" == "release" ]]; then echo "true"; else echo "false"; fi)

[build]
# Build for current host
build = "$(rustc -vV | grep host | cut -d' ' -f2)"
host = ["$(rustc -vV | grep host | cut -d' ' -f2)"]
# Include M68k target
target = ["$(rustc -vV | grep host | cut -d' ' -f2)", "m68k-unknown-linux-gnu"]
# Use all available cores
jobs = 0
# Extended build includes more tools
extended = true
tools = ["cargo", "rustfmt", "clippy"]
# Reduce memory usage by building fewer things in parallel
codegen-units = 1
# Enable verbose output
verbose = 2
# Use our build directory
build-dir = "$RUST_BUILD_DIR"

[rust]
# Release channel for stability
channel = "stable"
# Optimize in release mode
optimize = $(if [[ "$BUILD_TYPE" == "release" ]]; then echo "true"; else echo "false"; fi)
# Include debug info even in release
debuginfo-level = 1
# Enable all CPU features
codegen-units = 1
# Link-time optimization in release
lto = $(if [[ "$BUILD_TYPE" == "release" ]]; then echo '"thin"'; else echo '"off"'; fi)

[dist]
# Don't compress for faster builds
compression-formats = ["gz"]

# Target-specific configuration
[target.m68k-unknown-linux-gnu]
# Use our custom LLVM
llvm-config = "$CUSTOM_LLVM_DIR/bin/llvm-config"
EOF

# Apply any necessary patches for M68k support
if [[ -d "$PROJECT_ROOT/patches/rust" ]]; then
    echo "Applying Rust patches..."
    for patch in "$PROJECT_ROOT/patches/rust"/*.patch; do
        if [[ -f "$patch" ]]; then
            echo "  - Applying $(basename "$patch")"
            git apply --check "$patch" 2>/dev/null || {
                echo "    Patch already applied or conflicts, skipping"
                continue
            }
            git apply "$patch"
        fi
    done
fi

# Add our M68k target specification
TARGET_SPEC_DIR="$RUST_SRC_DIR/compiler/rustc_target/src/spec/targets"
if [[ ! -f "$TARGET_SPEC_DIR/m68k_next_nextstep.rs" ]]; then
    echo "Adding M68k NeXTSTEP target specification..."
    cat > "$TARGET_SPEC_DIR/m68k_next_nextstep.rs" << 'EOF'
use crate::spec::{Cc, LinkerFlavor, Lld, Target, TargetOptions};

pub fn target() -> Target {
    Target {
        llvm_target: "m68k-next-nextstep".into(),
        metadata: crate::spec::TargetMetadata {
            description: Some("M68k NeXTSTEP".into()),
            tier: Some(3),
            host_tools: Some(false),
            std: Some(false),
        },
        pointer_width: 32,
        data_layout: "E-m:e-p:32:32-i64:64-n8:16:32".into(),
        arch: "m68k".into(),
        
        options: TargetOptions {
            endian: crate::spec::Endian::Big,
            c_int_width: "32".into(),
            cpu: "m68040".into(),
            features: "+m68040".into(),
            max_atomic_width: Some(32),
            atomic_cas: false, // No native CAS on m68k
            panic_strategy: crate::spec::PanicStrategy::Abort,
            linker_flavor: LinkerFlavor::Unix(Cc::Yes),
            linker: Some("clang".into()),
            pre_link_args: [(
                LinkerFlavor::Unix(Cc::Yes),
                vec![
                    "-target".into(),
                    "m68k-next-nextstep".into(),
                    "-nostdlib".into(),
                ],
            )]
            .into_iter()
            .collect(),
            os: "nextstep".into(),
            env: "".into(),
            vendor: "next".into(),
            has_rpath: false,
            position_independent_executables: false,
            static_position_independent_executables: false,
            needs_plt: false,
            relro_level: crate::spec::RelroLevel::None,
            code_model: Some(crate::spec::CodeModel::Large),
            ..Default::default()
        },
    }
}
EOF
    
    # Register the target in mod.rs
    echo 'mod m68k_next_nextstep;' >> "$TARGET_SPEC_DIR/mod.rs"
    # Add to the target list (this is fragile, may need manual editing)
    sed -i '' 's/];$/    ("m68k-next-nextstep", m68k_next_nextstep),\n];/' "$TARGET_SPEC_DIR/mod.rs" 2>/dev/null || {
        echo "Warning: Could not automatically register target. Manual edit of mod.rs required."
    }
fi

# Build rustc
echo "Building rustc stage $STAGE (this will take a while)..."
echo "Tip: Monitor progress with: tail -f $RUST_BUILD_DIR/bootstrap-build.log"

# Set up environment
export RUST_BACKTRACE=1
export CARGO_INCREMENTAL=0  # Disable incremental compilation for reliability

# Use python3 explicitly
PYTHON_CMD="python3"
if ! command -v python3 &> /dev/null; then
    PYTHON_CMD="python"
fi

# Build
time $PYTHON_CMD x.py build --stage "$STAGE" \
    --config config.toml \
    2>&1 | tee "$RUST_BUILD_DIR/bootstrap-build.log"

if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    echo "Error: Rust build failed!" >&2
    echo "Check the build log: $RUST_BUILD_DIR/bootstrap-build.log" >&2
    exit 1
fi

# Install to a local directory for testing
INSTALL_DIR="$PROJECT_ROOT/custom-rustc"
echo "Installing to $INSTALL_DIR..."
$PYTHON_CMD x.py install --stage "$STAGE" --prefix="$INSTALL_DIR"

# Create a wrapper script
cat > "$INSTALL_DIR/bin/m68k-rustc" << EOF
#!/bin/bash
# Wrapper for custom rustc with M68k support
export LD_LIBRARY_PATH="$INSTALL_DIR/lib:\$LD_LIBRARY_PATH"
export DYLD_LIBRARY_PATH="$INSTALL_DIR/lib:\$DYLD_LIBRARY_PATH"
exec "$INSTALL_DIR/bin/rustc" "\$@"
EOF
chmod +x "$INSTALL_DIR/bin/m68k-rustc"

# Test the build
echo "Testing custom rustc..."
"$INSTALL_DIR/bin/rustc" --version
"$INSTALL_DIR/bin/rustc" --print target-list | grep m68k || {
    echo "Warning: M68k targets not found in rustc output"
}

echo "=== Custom rustc build complete! ==="
echo "Installation directory: $INSTALL_DIR"
echo "To use this rustc:"
echo "  export PATH=\"$INSTALL_DIR/bin:\$PATH\""
echo "Or link it as a rustup toolchain:"
echo "  rustup toolchain link nextrust-m68k $INSTALL_DIR"

# Create a summary file
cat > "$PROJECT_ROOT/custom-rustc-build.txt" << EOF
Custom Rustc Build Summary
========================
Date: $(date)
Rust version: $RUSTC_VERSION
Stage: $STAGE
Build type: $BUILD_TYPE
LLVM: $CUSTOM_LLVM_DIR
Install dir: $INSTALL_DIR

To use:
  rustup toolchain link nextrust-m68k $INSTALL_DIR
  cargo +nextrust-m68k build --target m68k-next-nextstep
EOF

echo "Build summary saved to: $PROJECT_ROOT/custom-rustc-build.txt"