# Rust 1.77 Build Guide for NeXTRust

**Last Updated**: July 22, 2025 4:27 PM EEST

This document details all changes and steps required to successfully build Rust 1.77 with custom LLVM 17 patches for the m68k-next-nextstep target.

## Prerequisites

1. **macOS on Apple Silicon (M1/M2/M3)**
   - Tested on macOS 15.5 (Darwin 24.5.0)
   - Requires Xcode Command Line Tools

2. **Homebrew packages**:
   ```bash
   brew install cmake ninja ccache zstd
   ```

3. **Python 3** (for Rust build system)

## Critical Changes Required

### 1. LLVM Build Configuration

**File**: `ci/scripts/build-custom-llvm.sh`

**Change**: Add AArch64 target support for Apple Silicon hosts

```bash
# Line 110 - MUST include AArch64 for M1/M2/M3 Macs
-DLLVM_TARGETS_TO_BUILD="X86;M68k;AArch64" \
```

**Reason**: Without AArch64, rustc build fails with:
```
No available targets are compatible with triple "arm64-apple-macosx11.0.0"
```

### 2. Environment Variables

**Required for zstd library linking**:
```bash
export LIBRARY_PATH="/opt/homebrew/lib:$LIBRARY_PATH"
export CPATH="/opt/homebrew/include:$CPATH"
```

**Reason**: Rust build system doesn't automatically find Homebrew libraries on Apple Silicon.

### 3. Rust Configuration

**File**: `rust-1.77/config.toml`

```toml
# Rust 1.77 build configuration for NeXTRust
# Compatible with LLVM 17

profile = "compiler"

[llvm]
download-ci-llvm = false
link-shared = false
assertions = false
ccache = false

[target.aarch64-apple-darwin]
llvm-config = "/Users/johnfabienke/Development/NeXTRust/toolchain/bin/llvm-config"

[build]
build = "aarch64-apple-darwin"
host = ["aarch64-apple-darwin"]
target = ["aarch64-apple-darwin"]
extended = true
tools = ["cargo", "rustdoc", "clippy", "rustfmt"]
verbose = 1
build-dir = "/Users/johnfabienke/Development/NeXTRust/build/rust-1.77"
docs = false

[rust]
channel = "stable"
debuginfo-level = 1
codegen-units = 16
lto = "off"
rpath = false
```

## Build Process

### Step 1: Build Custom LLVM

```bash
cd /Users/johnfabienke/Development/NeXTRust
./ci/scripts/build-custom-llvm.sh
```

This applies our M68k patches and builds LLVM with:
- M68k Mach-O object writer support
- M68k scheduling model (prevents rustc crashes)
- FileCheck utility (required for Rust tests)
- X86, M68k, and AArch64 targets

### Step 2: Clone Rust 1.77

```bash
git clone --branch 1.77.0 --depth 1 https://github.com/rust-lang/rust.git rust-1.77
cd rust-1.77
```

### Step 3: Configure Rust Build

1. Create the config.toml file (shown above)
2. Set environment variables:
   ```bash
   export LIBRARY_PATH="/opt/homebrew/lib:$LIBRARY_PATH"
   export CPATH="/opt/homebrew/include:$CPATH"
   ```

### Step 4: Build Rust

**Option A: Full build (may fail with dsymutil errors)**
```bash
python3 x.py build --stage 1
```

**Option B: Compiler-only build (recommended)**
```bash
python3 x.py build --stage 1 compiler/rustc
```

### Step 5: Verify Build

```bash
# Check rustc was built
ls -la build/*/stage1/bin/rustc

# Verify version and LLVM
build/*/stage1/bin/rustc --version --verbose
# Should show: LLVM version: 17.0.6
```

## Common Issues and Solutions

### 1. zstd Library Not Found

**Error**:
```
ld: library 'zstd' not found
```

**Solution**: Set LIBRARY_PATH and CPATH as shown above.

### 2. AArch64 Target Missing

**Error**:
```
LLVM ERROR: Cannot create target machine: No available targets are compatible with triple "arm64-apple-macosx"
```

**Solution**: Rebuild LLVM with AArch64 in LLVM_TARGETS_TO_BUILD.

### 3. dsymutil Errors

**Error**:
```
error: cannot parse the debug map for '/dev/null': The file was not recognized as a valid object file
clang: error: dsymutil command failed with exit code 1
```

**Solution**: Build only the compiler without tools:
```bash
python3 x.py build --stage 1 compiler/rustc
```

Or disable debug info splitting:
```bash
export CARGO_PROFILE_RELEASE_SPLIT_DEBUGINFO=off
```

### 4. FileCheck Not Found

**Error**: Rust tests fail due to missing FileCheck

**Solution**: Ensure LLVM was built with:
```cmake
-DLLVM_INSTALL_UTILS=ON
```

## Build Times

- **LLVM Build**: ~45 minutes (M2 Pro with 8 cores)
- **Rust Build (compiler only)**: ~5 minutes with cache, ~30 minutes clean
- **Full Rust Build**: ~1-2 hours (if successful)

## Using the Built Compiler

### For Host Development

```bash
# Use directly
/path/to/build/*/stage1/bin/rustc your_code.rs

# Or add to PATH
export PATH="/path/to/build/*/stage1/bin:$PATH"
```

### For M68k Cross-Compilation

```bash
# Requires nightly features for custom targets
# Use rustup nightly instead, with our LLVM as backend
rustup install nightly
rustup component add rust-src --toolchain nightly

# Then use with our target spec
cargo +nightly build \
  --target /path/to/targets/m68k-next-nextstep.json \
  -Z build-std=core,alloc
```

## Verification Checklist

- [ ] LLVM builds successfully with M68k patches
- [ ] FileCheck is installed in toolchain/bin/
- [ ] LLVM supports X86, M68k, and AArch64 targets
- [ ] Rust 1.77 builds without errors
- [ ] rustc --version shows LLVM 17.0.6
- [ ] Simple Rust programs compile for host

## Future Improvements

1. **Automate the build process**:
   - Create a single script that handles all steps
   - Add error detection and recovery

2. **Cache management**:
   - Save built artifacts for CI
   - Create Docker image with pre-built toolchain

3. **Debug the dsymutil issue**:
   - Investigate why full builds fail on macOS
   - May require patches to Rust's build system

## Related Documentation

- [Toolchain Modifications](toolchain-modifications.md)
- [LLVM Patches](../patches/llvm/README.md)
- [Target Specification](../targets/m68k-next-nextstep.json)

---

This guide will be updated as we discover new requirements or optimizations.