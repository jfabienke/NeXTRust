#!/bin/bash
# Two-phase rustc bootstrap for NeXTRust
# Avoids m68k target detection crash by building in phases
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUST_DIR="$PROJECT_ROOT/rust"
CUSTOM_LLVM_DIR="$PROJECT_ROOT/toolchain"
BUILD_DIR="$PROJECT_ROOT/build/rust"
CARGO_CONFIG="$PROJECT_ROOT/.cargo/config.toml"
CARGO_CONFIG_BACKUP="$PROJECT_ROOT/.cargo/config.toml.backup"

echo "=== Two-Phase Rustc Bootstrap for NeXTRust ==="
echo "This avoids the m68k target detection crash during bootstrap"

# Check prerequisites
if [[ ! -f "$CUSTOM_LLVM_DIR/bin/llvm-config" ]]; then
    echo "Error: Custom LLVM not found. Run build-custom-llvm.sh first." >&2
    exit 1
fi

if [[ ! -d "$RUST_DIR" ]]; then
    echo "Error: Rust source not found at $RUST_DIR" >&2
    echo "Run: git clone https://github.com/rust-lang/rust.git $RUST_DIR" >&2
    exit 1
fi

# Phase 1: Build host-only rustc
echo ""
echo "=== PHASE 1: Building host-only rustc ==="
echo "This builds rustc without m68k target to avoid crashes"

# Temporarily move cargo config to prevent m68k target detection
if [[ -f "$CARGO_CONFIG" ]]; then
    echo "Moving .cargo/config.toml aside temporarily..."
    mv "$CARGO_CONFIG" "$CARGO_CONFIG_BACKUP"
fi

cd "$RUST_DIR"

# Create phase 1 config - host only
cat > config.toml << EOF
# Phase 1: Host-only build with custom LLVM
profile = "compiler"

[llvm]
download-ci-llvm = false
llvm-config = "$CUSTOM_LLVM_DIR/bin/llvm-config"
link-shared = false
assertions = false
ccache = false

[build]
build = "aarch64-apple-darwin"
host = ["aarch64-apple-darwin"]
target = ["aarch64-apple-darwin"]
extended = true
tools = ["cargo", "rustdoc", "clippy", "rustfmt"]
verbose = 1
build-dir = "$BUILD_DIR"
docs = false

[rust]
channel = "dev"
debuginfo-level = 1
codegen-units = 16
lto = "off"
rpath = false
EOF

echo "Building phase 1 (this will take a while)..."
python3 x.py build --stage 1 2>&1 | tee "$PROJECT_ROOT/rustc-phase1.log" || {
    echo "Phase 1 build failed!" >&2
    # Restore cargo config
    [[ -f "$CARGO_CONFIG_BACKUP" ]] && mv "$CARGO_CONFIG_BACKUP" "$CARGO_CONFIG"
    exit 1
}

echo "Phase 1 complete!"

# Phase 2: Add m68k target
echo ""
echo "=== PHASE 2: Adding m68k target support ==="

# Add m68k target to rustc sources
TARGET_SPEC_DIR="$RUST_DIR/compiler/rustc_target/src/spec/targets"
if [[ ! -f "$TARGET_SPEC_DIR/m68k_next_nextstep.rs" ]]; then
    echo "Adding m68k-next-nextstep target specification..."
    cat > "$TARGET_SPEC_DIR/m68k_next_nextstep.rs" << 'EOF'
use crate::spec::{Cc, LinkerFlavor, Lld, Target, TargetOptions};
use crate::spec::base;

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
            max_atomic_width: Some(0), // No atomics
            atomic_cas: false,
            panic_strategy: crate::spec::PanicStrategy::Abort,
            linker_flavor: LinkerFlavor::Unix(Cc::Yes),
            linker: Some("clang".into()),
            executables: true,
            has_rpath: false,
            position_independent_executables: false,
            static_position_independent_executables: false,
            needs_plt: false,
            relro_level: crate::spec::RelroLevel::None,
            code_model: Some(crate::spec::CodeModel::Large),
            disable_redzone: true,
            emit_debug_gdb_scripts: false,
            supports_xray: false,
            ..base::nextstep::opts()
        },
    }
}
EOF

    # Create base nextstep module if it doesn't exist
    BASE_SPEC_DIR="$RUST_DIR/compiler/rustc_target/src/spec/base"
    if [[ ! -f "$BASE_SPEC_DIR/nextstep.rs" ]]; then
        echo "Creating base nextstep module..."
        cat > "$BASE_SPEC_DIR/nextstep.rs" << 'EOF'
use crate::spec::{cvs, TargetOptions};

pub fn opts() -> TargetOptions {
    TargetOptions {
        os: "nextstep".into(),
        vendor: "next".into(),
        dynamic_linking: false,
        executables: true,
        families: cvs!["unix"],
        has_rpath: false,
        position_independent_executables: false,
        linker_is_gnu: true,
        pre_link_args_crt: false,
        requires_lld: false,
        ..Default::default()
    }
}
EOF
        
        # Add to base/mod.rs
        echo 'pub(crate) mod nextstep;' >> "$BASE_SPEC_DIR/mod.rs"
    fi
    
    # Register the target in mod.rs
    if ! grep -q "m68k_next_nextstep" "$TARGET_SPEC_DIR/mod.rs"; then
        echo "Registering m68k-next-nextstep target..."
        # Add module declaration
        echo 'mod m68k_next_nextstep;' >> "$TARGET_SPEC_DIR/mod.rs"
        
        # Add to target list (this is fragile, may need manual editing)
        sed -i.bak '/^];$/i\    ("m68k-next-nextstep", m68k_next_nextstep::target),' "$TARGET_SPEC_DIR/mod.rs"
    fi
fi

# Update config for phase 2
cat > config.toml << EOF
# Phase 2: Add m68k target using phase 1 rustc
profile = "compiler"

[llvm]
download-ci-llvm = false
llvm-config = "$CUSTOM_LLVM_DIR/bin/llvm-config"
link-shared = false
assertions = false

[build]
build = "aarch64-apple-darwin"
host = ["aarch64-apple-darwin"]
target = ["aarch64-apple-darwin", "m68k-next-nextstep"]
extended = true
tools = ["cargo", "rustdoc", "clippy", "rustfmt"]
verbose = 1
build-dir = "$BUILD_DIR"
docs = false
# Use phase 1 rustc
rustc = "$BUILD_DIR/aarch64-apple-darwin/stage1/bin/rustc"
cargo = "$BUILD_DIR/aarch64-apple-darwin/stage1/bin/cargo"

[rust]
channel = "dev"
debuginfo-level = 1
codegen-units = 16
lto = "off"
rpath = false

[target.m68k-next-nextstep]
llvm-config = "$CUSTOM_LLVM_DIR/bin/llvm-config"
EOF

echo "Building phase 2 with m68k target..."
python3 x.py build --stage 2 2>&1 | tee "$PROJECT_ROOT/rustc-phase2.log" || {
    echo "Phase 2 build failed!" >&2
    # Restore cargo config
    [[ -f "$CARGO_CONFIG_BACKUP" ]] && mv "$CARGO_CONFIG_BACKUP" "$CARGO_CONFIG"
    exit 1
}

# Install the custom rustc
INSTALL_DIR="$PROJECT_ROOT/custom-rustc"
echo ""
echo "Installing custom rustc to $INSTALL_DIR..."
python3 x.py install --stage 2 --prefix="$INSTALL_DIR" || {
    echo "Installation failed!" >&2
    exit 1
}

# Restore cargo config
if [[ -f "$CARGO_CONFIG_BACKUP" ]]; then
    echo "Restoring .cargo/config.toml..."
    mv "$CARGO_CONFIG_BACKUP" "$CARGO_CONFIG"
fi

# Test the custom rustc
echo ""
echo "Testing custom rustc..."
"$INSTALL_DIR/bin/rustc" --version
"$INSTALL_DIR/bin/rustc" --print target-list | grep m68k || {
    echo "Warning: m68k targets not found in rustc output"
}

# Create rustup toolchain link
echo ""
echo "Creating rustup toolchain link..."
rustup toolchain link nextrust-m68k "$INSTALL_DIR"

echo ""
echo "=== Two-phase rustc bootstrap complete! ==="
echo "To use: cargo +nextrust-m68k build --target targets/m68k-next-nextstep.json"
echo ""
echo "Next steps:"
echo "1. Test with: cargo +nextrust-m68k build --target targets/m68k-next-nextstep.json --example hello-simple"
echo "2. Set up emulator testing infrastructure"
echo "3. Implement atomic operations"