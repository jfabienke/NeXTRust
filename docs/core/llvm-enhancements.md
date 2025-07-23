# LLVM Enhancements for NeXTSTEP m68k Mach-O Support

*Last updated: 2025-07-23 00:58 EEST*

## ✅ NEW: Complete Instruction Scheduling Implementation (July 2025)

**Status:** COMPLETED - Zero missing itineraries with CompleteModel = 1 enabled

We have achieved **100% instruction scheduling coverage** for the M68k LLVM backend. This provides:
- ✅ Complete instruction scheduling for all 150+ M68k instructions
- ✅ Proper latency modeling for 68030/68040 processors  
- ✅ Enterprise-grade compiler optimization capabilities
- ✅ Production-ready code generation for NeXTSTEP

**Documentation:**
- **[Complete Implementation Guide](../llvm-enhancements/m68k-scheduling-complete.md)** - Comprehensive documentation
- **[Technical Changes Summary](../llvm-enhancements/m68k-scheduling-changes.md)** - Quick reference for all modifications

**Key Achievement:** Systematic implementation covering all instruction categories:
- Control Flow (branches, jumps, returns)
- Data Movement (moves, loads, stores, stack operations)  
- Arithmetic Operations (ALU, FPU, comparisons)
- Bit Operations (bit test variants)
- Atomic Operations (compare-and-swap)
- System Instructions (traps, condition codes)

This milestone establishes the M68k backend as production-ready for serious compiler use.

## Overview

This document details the LLVM modifications required to enable Mach-O object file generation for the m68k backend, specifically targeting NeXTSTEP. The upstream LLVM m68k backend currently only supports ELF output, so we must extend it with Mach-O capabilities while maintaining compatibility with the existing infrastructure.

## Core Modifications

### 1. Triple Recognition

**File**: `llvm/lib/Support/Triple.cpp`

```cpp
// Add NeXTSTEP OS type recognition
static Triple::OSType parseOS(StringRef OSName) {
  return StringSwitch<Triple::OSType>(OSName)
    // ... existing cases ...
    .StartsWith("nextstep", Triple::NeXTSTEP)
    .Default(Triple::UnknownOS);
}

// Add NeXT vendor recognition
static Triple::VendorType parseVendor(StringRef VendorName) {
  return StringSwitch<Triple::VendorType>(VendorName)
    // ... existing cases ...
    .Case("next", Triple::NeXT)
    .Default(Triple::UnknownVendor);
}
```

**File**: `llvm/include/llvm/ADT/Triple.h`

```cpp
enum VendorType {
  // ... existing vendors ...
  NeXT,
};

enum OSType {
  // ... existing OSes ...
  NeXTSTEP,
};
```

### 2. M68k Mach-O Object Writer

**New File**: `llvm/lib/Target/M68k/MCTargetDesc/M68kMachObjectWriter.cpp`

```cpp
#include "MCTargetDesc/M68kFixupKinds.h"
#include "llvm/MC/MCMachObjectWriter.h"
#include "llvm/MC/MCValue.h"

namespace {
class M68kMachObjectWriter : public MCMachObjectTargetWriter {
public:
  M68kMachObjectWriter(bool Is64Bit, uint32_t CPUType)
      : MCMachObjectTargetWriter(Is64Bit, CPUType, 
                                 MachO::CPU_SUBTYPE_MC68030) {}

  void recordRelocation(MachObjectWriter *Writer, MCAssembler &Asm,
                       const MCAsmLayout &Layout, const MCFragment *Fragment,
                       const MCFixup &Fixup, MCValue Target,
                       uint64_t &FixedValue) override;
};
}

void M68kMachObjectWriter::recordRelocation(
    MachObjectWriter *Writer, MCAssembler &Asm,
    const MCAsmLayout &Layout, const MCFragment *Fragment,
    const MCFixup &Fixup, MCValue Target, uint64_t &FixedValue) {
  
  const MCSymbol *A = &Target.getSymA()->getSymbol();
  const MCSymbol *B = Target.getSymB() ? 
                      &Target.getSymB()->getSymbol() : nullptr;
  
  // Handle scattered relocations for symbol differences
  if (B) {
    // NeXTSTEP uses scattered relocations for 32-bit diffs
    MachO::scattered_relocation_info SRI;
    SRI.r_scattered = 1;
    SRI.r_pcrel = 0;
    SRI.r_length = 2; // 32-bit
    SRI.r_type = MachO::GENERIC_RELOC_SECTDIFF;
    SRI.r_value = Layout.getSymbolOffset(*A);
    
    // Write PAIR relocation
    MachO::scattered_relocation_info PairSRI;
    PairSRI.r_scattered = 1;
    PairSRI.r_pcrel = 0;
    PairSRI.r_length = 2;
    PairSRI.r_type = MachO::GENERIC_RELOC_PAIR;
    PairSRI.r_value = Layout.getSymbolOffset(*B);
    
    Writer->addRelocation(Fragment, SRI);
    Writer->addRelocation(Fragment, PairSRI);
    return;
  }
  
  // Handle regular relocations
  unsigned Type = unsigned(MachO::GENERIC_RELOC_VANILLA);
  switch (Fixup.getKind()) {
  case M68k::fixup_M68k_PC32:
    Type = MachO::GENERIC_RELOC_PCREL;
    break;
  case M68k::fixup_M68k_32:
    Type = MachO::GENERIC_RELOC_VANILLA;
    break;
  // Add more fixup mappings
  }
  
  MachO::any_relocation_info MRE;
  MRE.r_word0 = FixupOffset;
  MRE.r_word1 = ((Index << 0) |
                 (IsPCRel << 24) |
                 (Log2Size << 25) |
                 (Type << 28));
  
  Writer->addRelocation(Fragment, MRE);
}
```

### 3. M68k Assembly Backend Mach-O Support

**File**: `llvm/lib/Target/M68k/MCTargetDesc/M68kAsmBackend.cpp`

```cpp
namespace {
class M68kAsmBackendMachO : public M68kAsmBackend {
public:
  M68kAsmBackendMachO(const MCSubtargetInfo &STI)
      : M68kAsmBackend(STI) {}

  std::unique_ptr<MCObjectTargetWriter>
  createObjectTargetWriter() const override {
    return createM68kMachObjectWriter(
        /*Is64Bit=*/false, MachO::CPU_TYPE_MC680x0);
  }
  
  bool evaluateTargetFixup(const MCAssembler &Asm,
                          const MCAsmLayout &Layout,
                          const MCFixup &Fixup,
                          const MCFragment *DF,
                          const MCValue &Target,
                          uint64_t &Value) const override {
    // Special handling for Mach-O symbol differences
    if (Target.getSymB()) {
      const MCSymbol &SA = Target.getSymA()->getSymbol();
      const MCSymbol &SB = Target.getSymB()->getSymbol();
      
      // Calculate symbol difference at assembly time if possible
      if (SA.getFragment() == SB.getFragment()) {
        Value = Layout.getSymbolOffset(SA) - Layout.getSymbolOffset(SB);
        return true;
      }
    }
    return false;
  }
};
}

MCAsmBackend *llvm::createM68kAsmBackend(const Target &T,
                                         const MCSubtargetInfo &STI,
                                         const MCRegisterInfo &MRI,
                                         const MCTargetOptions &Options) {
  const Triple &TT = STI.getTargetTriple();
  
  if (TT.isOSBinFormatMachO())
    return new M68kAsmBackendMachO(STI);
  
  return new M68kAsmBackendELF(STI);
}
```

### 4. Large Code Model Support

**File**: `llvm/lib/Target/M68k/M68kTargetMachine.cpp`

```cpp
static Reloc::Model getEffectiveRelocModel(const Triple &TT,
                                          Optional<Reloc::Model> RM) {
  if (!RM.hasValue()) {
    // NeXTSTEP requires static relocation for kernel/drivers
    if (TT.getOS() == Triple::NeXTSTEP)
      return Reloc::Static;
    return Reloc::PIC_;
  }
  return *RM;
}

static CodeModel::Model getEffectiveCodeModel(const Triple &TT,
                                             Optional<CodeModel::Model> CM,
                                             bool JIT) {
  if (!CM) {
    // NeXTSTEP often has separated ROM/RAM requiring large model
    if (TT.getOS() == Triple::NeXTSTEP)
      return CodeModel::Large;
    return CodeModel::Small;
  }
  return *CM;
}
```

### 5. M68k MC Layer Integration

**File**: `llvm/lib/Target/M68k/MCTargetDesc/M68kMCTargetDesc.cpp`

```cpp
static MCStreamer *createM68kMCStreamer(const Triple &T, MCContext &Context,
                                       std::unique_ptr<MCAsmBackend> &&MAB,
                                       std::unique_ptr<MCObjectWriter> &&OW,
                                       std::unique_ptr<MCCodeEmitter> &&Emitter,
                                       bool RelaxAll) {
  if (T.isOSBinFormatMachO())
    return createMachOStreamer(Context, std::move(MAB), std::move(OW),
                              std::move(Emitter), RelaxAll,
                              /*DWARFMustBeAtTheEnd=*/false);
  
  return createELFStreamer(Context, std::move(MAB), std::move(OW),
                          std::move(Emitter), RelaxAll);
}
```

### 6. Relocation Processing

**File**: `llvm/lib/Target/M68k/MCTargetDesc/M68kMachORelocationInfo.cpp`

```cpp
/// Convert generic Mach-O relocations to M68k-specific fixups
class M68kMachORelocationInfo : public MCRelocationInfo {
public:
  M68kMachORelocationInfo(MCContext &Ctx) : MCRelocationInfo(Ctx) {}

  unsigned getFixupKindForReloc(unsigned Type, bool IsPCRel,
                               unsigned Log2Size) const {
    switch (Type) {
    case MachO::GENERIC_RELOC_VANILLA:
      switch (Log2Size) {
      case 0: return M68k::fixup_M68k_8;
      case 1: return M68k::fixup_M68k_16;
      case 2: return M68k::fixup_M68k_32;
      }
      break;
    case MachO::GENERIC_RELOC_PCREL:
      switch (Log2Size) {
      case 0: return M68k::fixup_M68k_PC8;
      case 1: return M68k::fixup_M68k_PC16;
      case 2: return M68k::fixup_M68k_PC32;
      }
      break;
    case MachO::GENERIC_RELOC_SECTDIFF:
      return M68k::fixup_M68k_32_DIFF;
    }
    llvm_unreachable("Unknown relocation type");
  }
};
```

### 7. Expression Evaluation for Mach-O

**File**: `llvm/lib/MC/MCExpr.cpp`

```cpp
// Enhance constant folding for Mach-O symbol differences
bool MCExpr::evaluateAsRelocatableImpl(MCValue &Res, const MCAssembler *Asm,
                                       const MCAsmLayout *Layout,
                                       const MCFixup *Fixup,
                                       const SectionAddrMap *Addrs) const {
  // ... existing code ...
  
  // Special case for Mach-O on m68k with scattered relocations
  if (Asm && Asm->getContext().getObjectFileType() == MCContext::IsMachO) {
    const Triple &TT = Asm->getContext().getTargetTriple();
    if (TT.getArch() == Triple::m68k) {
      // Allow symbol differences to be resolved at link time
      // via scattered relocations
      if (LHSValue.getSymA() && RHSValue.getSymA()) {
        Res = MCValue::get(LHSValue.getSymA(), RHSValue.getSymA(),
                          LHSValue.getConstant() - RHSValue.getConstant());
        return true;
      }
    }
  }
}
```

## Testing Infrastructure

### Unit Tests

**File**: `llvm/unittests/Target/M68k/M68kMachOTest.cpp`

```cpp
TEST(M68kMachO, ScatteredRelocation) {
  // Test scattered relocation generation
  std::string AsmString = R"(
    .text
    _start:
      move.l #(_end - _start), d0
    _end:
  )";
  
  // Verify scattered relocation is generated
  auto Relocations = parseAndGetRelocations(AsmString);
  EXPECT_EQ(Relocations.size(), 2);
  EXPECT_TRUE(Relocations[0].r_scattered);
  EXPECT_EQ(Relocations[0].r_type, MachO::GENERIC_RELOC_SECTDIFF);
  EXPECT_EQ(Relocations[1].r_type, MachO::GENERIC_RELOC_PAIR);
}
```

### Integration Tests

```bash
# Test LLVM compilation
cat > test.c << EOF
int main() {
    const char msg[] = "Hello, NeXTSTEP!";
    return 0;
}
EOF

# Compile to Mach-O
clang -target m68k-next-nextstep -c test.c -o test.o

# Verify Mach-O format
otool -h test.o | grep "MC680x0"
```

## Build System Integration

**File**: `llvm/lib/Target/M68k/CMakeLists.txt`

```cmake
add_llvm_target(M68kCodeGen
  # ... existing files ...
  MCTargetDesc/M68kMachObjectWriter.cpp
  MCTargetDesc/M68kMachORelocationInfo.cpp
)
```

## Patch Management

### Directory Structure
```
patches/llvm/
   0001-triple-recognition.patch
   0002-mach-o-object-writer.patch
   0003-asm-backend-mach-o.patch
   0004-large-code-model.patch
   0005-mc-layer-integration.patch
   0006-relocation-processing.patch
   0007-expression-evaluation.patch
```

### Applying Patches
```bash
#!/bin/bash
# ci/scripts/apply-llvm-patches.sh

cd vendor/llvm
for patch in ../../patches/llvm/*.patch; do
    git apply "$patch" || exit 1
done
```

## Known Issues and Workarounds

### 1. Symbol Resolution
- **Issue**: NeXTSTEP's early dyld has limited symbol resolution
- **Workaround**: Use two-level namespace with explicit library dependencies

### 2. Alignment Requirements
- **Issue**: m68k requires strict alignment for some instructions
- **Workaround**: Force 4-byte alignment for code sections

### 3. Debug Information
- **Issue**: NeXTSTEP gdb expects STABS, not DWARF
- **Workaround**: Disable DWARF generation, implement minimal STABS

## Performance Optimizations

### 1. Instruction Selection
```cpp
// Optimize for 68030/68040 instruction timings
def : Pat<(add i32:$src, (i32 1)),
          (ADDQ_I 1, $src)>;  // ADDQ is faster than ADD #1
```

### 2. Addressing Modes
```cpp
// Leverage m68k's rich addressing modes
def : Pat<(load (add i32:$base, i32:$index)),
          (MOVE32rm $base, $index)>;  // Use indexed addressing
```

## Future Enhancements

1. **Link-Time Optimization (LTO)**: Add Mach-O LTO support
2. **Bitcode Embedding**: Store LLVM bitcode in Mach-O sections
3. **Profile-Guided Optimization**: Port instrumentation runtime
4. **Advanced Relocations**: Support for lazy binding stubs
5. **Universal Binaries**: Multiple m68k variants in one file
6. **DSP Coprocessor Integration** (Research): Explore using DSP56001 for transcendental functions - see [feasibility study](../hardware/dsp-transcendental-functions.md)

## References

- [Mach-O File Format Reference](https://github.com/aidansteele/osx-abi-macho-file-format-reference)
- [LLVM MC Layer](https://llvm.org/docs/CodeGenerator.html#the-mc-layer)
- [NeXTSTEP Developer Documentation](http://www.nextcomputers.org/NeXTfiles/Docs/NeXTStep/)
- [M68k Relocation Types](../references/M68000PRM.pdf)

## Related Documentation

### M68k Instruction Set and Compatibility
- **[M68k Instruction Set Implementation Status](../llvm-enhancements/m68k-instruction-set-status.md)** - Complete overview of which M68k instructions are implemented in LLVM
- **[M68060 Removed Instructions](../llvm-enhancements/m68060-removed-instructions.md)** - Instructions removed in 68060 for superscalar design
- **[M68k Emulator Compatibility Guide](../llvm-enhancements/m68k-emulator-compatibility.md)** - Testing on Previous, MAME, and other emulators
- **[M68k ISA Evolution for LLVM](../llvm-enhancements/m68k-isa-evolution-llvm.md)** - How to leverage ISA evolution knowledge in the LLVM backend
- **[M68k Instruction Set Evolution](../hardware/m68k-instruction-set-evolution.md)** - Complete history of M68k family from 68000 to Apollo 68080