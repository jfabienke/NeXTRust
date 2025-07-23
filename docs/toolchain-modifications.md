# NeXTRust Toolchain Modifications Documentation

**Last Updated**: July 22, 2025 10:57 PM EEST

This document comprehensively lists all modifications made to LLVM and Rust for the NeXTRust project. Use this as a reference when upgrading to newer LLVM/Rust versions.

## Table of Contents

1. [LLVM Modifications](#llvm-modifications)
2. [Rust Configuration](#rust-configuration)
3. [Build Process Changes](#build-process-changes)
4. [Migration Guide](#migration-guide)
5. [Version Compatibility Matrix](#version-compatibility-matrix)

## LLVM Modifications

### 1. Mach-O Object File Support (`patches/llvm/0001-m68k-mach-o-support.patch`)

This is the primary patch that enables NeXTSTEP Mach-O object file generation for M68k targets.

#### Files Modified:
- `llvm/lib/Target/M68k/MCTargetDesc/CMakeLists.txt`
- `llvm/lib/Target/M68k/MCTargetDesc/M68kAsmBackend.cpp`
- `llvm/lib/Target/M68k/MCTargetDesc/M68kMCTargetDesc.h`
- `llvm/lib/Target/M68k/MCTargetDesc/M68kMachObjectWriter.cpp` (new file)

#### Key Changes:

**CMakeLists.txt**:
```cmake
add_llvm_component_library(LLVMM68kDesc
  M68kAsmBackend.cpp
  M68kELFObjectWriter.cpp
+ M68kMachObjectWriter.cpp  # Added for Mach-O support
  M68kInstPrinter.cpp
```

**M68kAsmBackend.cpp**:
- Added `M68kMachOAsmBackend` class
- Modified `createM68kAsmBackend` to detect NeXTSTEP/Mach-O targets:
  ```cpp
  if (TheTriple.isOSBinFormatMachO() || 
      TheTriple.getOS() == Triple::Darwin ||
      TheTriple.getOSName() == "nextstep") {
    return new M68kMachOAsmBackend(T);
  }
  ```
- Routes to Mach-O object writer instead of ELF for NeXTSTEP

**M68kMachObjectWriter.cpp** (new file):
- Implements Mach-O object file writing for M68k
- Handles scattered relocations for 32-bit symbol differences
- Critical for switch tables and compiler-generated constructs
- Uses CPU_TYPE_MC680x0 (6) with subtypes:
  - CPU_SUBTYPE_MC68030 (1)
  - CPU_SUBTYPE_MC68040 (2)
- Relocation types:
  - GENERIC_RELOC_VANILLA for standard relocations
  - R_SCATTERED flag for cross-section references

### 2. M68k Scheduling Model (`llvm/lib/Target/M68k/M68kSchedule.td`)

Added to prevent rustc SIGSEGV crashes during optimization passes.

#### Key Additions:

**Instruction Itinerary Classes**:
```tablegen
def IIC_ALU       : InstrItinClass;
def IIC_ALU_MEM   : InstrItinClass;
def IIC_LOAD      : InstrItinClass;
def IIC_STORE     : InstrItinClass;
def IIC_BRANCH    : InstrItinClass;
def IIC_CALL      : InstrItinClass;
def IIC_RET       : InstrItinClass;
def IIC_FPU       : InstrItinClass;
def IIC_SHIFT     : InstrItinClass;
def IIC_MULTIPLY  : InstrItinClass;
def IIC_DIVIDE    : InstrItinClass;
def IIC_DEFAULT   : InstrItinClass;
```

**Functional Units**:
```tablegen
def M68kALU : FuncUnit; // Arithmetic Logic Unit
def M68kFPU : FuncUnit; // Floating Point Unit (68030+)
def M68kMem : FuncUnit; // Memory access unit
```

**Processor Models**:
- `GenericM68kModel`: Basic M68k with 4-cycle load latency
- `M68030Model`: 3-cycle load latency, 3-cycle misprediction penalty
- `M68040Model`: 2-cycle load latency, 4-cycle misprediction penalty

**Critical Setting**:
```tablegen
let CompleteModel = 0; // Prevents crashes from incomplete coverage
```

### 3. Build System Modifications

#### LLVM CMake Configuration (`ci/scripts/build-custom-llvm.sh`):
```bash
cmake ../llvm \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_TARGETS_TO_BUILD="X86;M68k" \
    -DLLVM_INSTALL_UTILS=ON \  # Critical for FileCheck
    -DCMAKE_BUILD_TYPE=Release
```

## Rust Configuration

### 1. Target Specification (`targets/m68k-next-nextstep.json`)

Custom target triple configuration for NeXTSTEP M68k:

```json
{
  "arch": "m68k",
  "os": "nextstep",
  "vendor": "next",
  "llvm-target": "m68k-next-nextstep",
  "data-layout": "E-m:e-p:32:16:32-i8:8:8-i16:16:16-i32:16:32-n8:16:32-a:0:16-S16",
  "target-endian": "big",
  "target-pointer-width": "32",
  "code-model": "large",        // For programs >64KB
  "atomic-cas": false,          // No native CAS support
  "min-atomic-width": 0,
  "max-atomic-width": 0,
  "panic-strategy": "abort",
  "dynamic-linking": false,
  "singlethread": true
}
```

### 2. Version Compatibility

- **Rust 1.77**: Last version supporting LLVM 17
- **Rust 1.78+**: Requires LLVM 18
- **Rust 1.81+**: Requires LLVM 19

### 3. Two-Phase Bootstrap Script

Created to avoid m68k target detection crashes during rustc build:

```bash
# Phase 1: Build host-only rustc with custom LLVM
mv .cargo/config.toml .cargo/config.toml.backup
python3 x.py build --stage 1

# Phase 2: Add m68k target support
mv .cargo/config.toml.backup .cargo/config.toml
# Configure m68k target in config.toml
python3 x.py build --stage 2 --target m68k-next-nextstep
```

## Build Process Changes

### 1. Custom LLVM Build Requirements

- Must include utility tools (FileCheck, etc.) for Rust tests
- Patches must be applied before building
- Build outputs to custom toolchain directory

### 2. Rust Build Configuration

**config.toml** for Rust 1.77:
```toml
[llvm]
download-ci-llvm = false
link-shared = false

[target.aarch64-apple-darwin]
llvm-config = "/path/to/custom/llvm/bin/llvm-config"

[build]
target = ["aarch64-apple-darwin"]  # Phase 1: host only
```

## Migration Guide

### When Upgrading to LLVM 18+

1. **Update LLVM Submodule**:
   ```bash
   git submodule update --init --remote llvm-project
   git -C llvm-project checkout release/18.x
   ```

2. **Rebase Patches**:
   - The Mach-O writer API is stable, minimal changes expected
   - Scheduling model format unchanged between 17→18
   - Watch for MCObjectTargetWriter API changes

3. **Update Rust Version**:
   - Use Rust 1.78+ for LLVM 18
   - Remove two-phase bootstrap workaround if fixed upstream

### Patch Application Order

1. Apply scheduling model changes first (prevents crashes)
2. Apply Mach-O support patch
3. Build LLVM with LLVM_INSTALL_UTILS=ON
4. Build Rust using custom LLVM

#### Patch Version Compatibility

| Patch | LLVM 17 | LLVM 18+ | Changes Required |
|-------|---------|----------|------------------|
| 0001-m68k-mach-o-support.patch | ✅ Direct apply | 🔄 Minor rebase | MCObjectTargetWriter API |
| M68kSchedule.td | ✅ Direct apply | ✅ Direct apply | TableGen format stable |
| Triple recognition | ✅ Implicit | 🔄 Check Triple.cpp | May need explicit OS enum |

### Testing After Upgrade

1. Verify LLVM builds without errors
2. Check FileCheck is installed: `ls toolchain/bin/FileCheck`
3. Build simple C test: `clang -target m68k-next-nextstep test.c`
4. Build Rust hello-world example
5. Run emulator tests: `./ci/scripts/run-emulator-tests.sh target/m68k-next-nextstep/debug/examples/hello-simple`

## Version Compatibility Matrix

| Rust Version | LLVM Version | Status | Notes |
|--------------|--------------|--------|-------|
| 1.73-1.77    | LLVM 17     | ✅ Supported | Current configuration |
| 1.78-1.80    | LLVM 18     | 🔄 Requires patch rebase | Minor API changes |
| 1.81+        | LLVM 19     | 🔄 Requires patch rebase | More significant changes |

## Troubleshooting

### Common Issues:

1. **FileCheck not found**: Rebuild LLVM with `LLVM_INSTALL_UTILS=ON`
2. **Rustc SIGSEGV**: Ensure scheduling model is applied
3. **Wrong object format**: Check triple detection in M68kAsmBackend
4. **Relocation errors**: Verify scattered relocation support

### Debug Commands:

```bash
# Check LLVM version
toolchain/bin/llvm-config --version

# Verify M68k target
toolchain/bin/llc -march=m68k -mattr=help

# Test object file generation
echo "int main() { return 0; }" > test.c
toolchain/bin/clang -target m68k-next-nextstep -c test.c
file test.o  # Should show "Mach-O object"
```

## Code Signing and Compatibility Notes

### NeXTSTEP Mach-O Limitations

NeXTSTEP uses an early version of Mach-O that predates many modern features:

- **No LC_CODE_SIGNATURE**: NeXTSTEP will reject binaries with code signature load commands
- **No LC_DYLD_INFO**: Dynamic linker info commands are not supported
- **Limited to 32-bit**: All addresses and offsets must fit in 32 bits
- **Scattered relocations only**: Modern relocation types will fail to load

Our Mach-O writer specifically targets this legacy format and avoids generating incompatible structures.

## Emulator Testing

After building the toolchain, validate binaries using the emulator test harness:

```bash
# Build a test binary
cargo +stage1 build --target=targets/m68k-next-nextstep.json \
    -Z build-std=core,alloc --example hello-simple

# Run in emulator (requires ROM and disk images)
./ci/scripts/run-emulator-tests.sh \
    target/m68k-next-nextstep/debug/examples/hello-simple

# Docker-based testing (if ROM/disk configured)
docker run --rm -v $(pwd):/workspace nextrust/previous-emulator \
    /workspace/target/m68k-next-nextstep/debug/examples/hello-simple
```

See `tests/harness/docker/Dockerfile.previous-emulator` for emulator configuration details.

## Critical Fixes Applied

### M68k Instruction Scheduling Fix (July 22, 2025)

**Problem**: SIGSEGV crashes when compiling for M68k targets
**Location**: `llvm/lib/Target/M68k/M68kSchedule.td`
**Fix**: Disable instruction scheduling entirely

```tablegen
class M68kSchedModel : SchedMachineModel {
  let LoadLatency = 4;
  let HighLatency = 16;
  let PostRAScheduler = 0;
  // Disable scheduling entirely to prevent crashes with incomplete model
  let NoModel = 1;  // ← Added this line
  let CompleteModel = 0;
}
```

**Impact**: Prevents crashes at the cost of potential performance optimizations. This is acceptable for initial target bring-up.

## Build Process Documentation

### Rust 1.77 Build Requirements

When building Rust 1.77 with our custom LLVM, the following additional requirements were discovered:

1. **AArch64 Target in LLVM**:
   - **Required for**: Apple Silicon Mac hosts (M1/M2/M3)
   - **Error without**: `No available targets are compatible with triple "arm64-apple-macosx"`
   - **Fix**: Add AArch64 to LLVM_TARGETS_TO_BUILD in build-custom-llvm.sh

2. **zstd Library Path**:
   - **Required for**: Linking rustc_driver
   - **Error without**: `ld: library 'zstd' not found`
   - **Fix**: Export LIBRARY_PATH and CPATH with Homebrew paths

3. **dsymutil Issues**:
   - **Problem**: Full builds fail with dsymutil errors on macOS
   - **Workaround**: Build only compiler with `python3 x.py build --stage 1 compiler/rustc`
   - **Alternative**: Disable split debuginfo

### Verified Build Configuration

**Date**: July 22, 2025
**Host**: macOS 15.5 on Apple Silicon
**LLVM**: 17.0.6 with M68k patches
**Rust**: 1.77.0 (last version supporting LLVM 17)
**Build Time**: ~5 minutes (cached), ~30 minutes (clean)

See [Rust 1.77 Build Guide](rust-1.77-build-guide.md) for detailed instructions.

## Future Considerations

1. **Upstream Contributions**: Consider submitting scheduling model upstream
2. **Mach-O Evolution**: Monitor Apple's Mach-O changes (unlikely for M68k)
3. **Rust Target Tier**: Work towards Tier 3 official support
4. **CI Integration**: Cache LLVM artifacts between builds
5. **Build Automation**: Create unified build script for LLVM + Rust

---

This document should be updated whenever toolchain modifications are made. For questions or issues, refer to the project's GitHub discussions.