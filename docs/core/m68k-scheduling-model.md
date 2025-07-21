# M68k Scheduling Model Documentation

**Last Updated**: July 21, 2025  
**Author**: NeXTRust Team  
**Status**: In Development

## Overview

This document describes the M68k scheduling model implementation for LLVM, created to support the m68k-next-nextstep Rust target. The scheduling model is essential for preventing compiler crashes and optimizing code generation for M68k processors.

## Background

The M68k backend in LLVM initially had a minimal scheduling model that caused rustc to crash during SelectionDAG scheduling. This was particularly problematic when compiling with optimizations enabled, as the scheduler expected complete scheduling information for all instructions.

## Architecture

### Scheduling Model Hierarchy

```
M68kSchedModel (base class)
├── GenericM68kModel (68000/68010/68020)
├── M68030Model (68030-specific timings)
└── M68040Model (68040-specific timings)
```

### Functional Units

The M68k processors are modeled with three primary functional units:

1. **M68kALU** - Arithmetic Logic Unit
   - Handles basic arithmetic, logic, and control operations
   - Single-cycle for most operations
   - Multi-cycle for complex operations (multiply, divide)

2. **M68kFPU** - Floating Point Unit (68030+)
   - Available on 68030 and later processors
   - Handles floating-point operations
   - Typically 4+ cycles per operation

3. **M68kMem** - Memory Access Unit
   - Handles load/store operations
   - Variable latency based on processor and memory type

### Instruction Itinerary Classes

| Class | Description | Typical Latency |
|-------|-------------|-----------------|
| IIC_ALU | Basic ALU operations (ADD, SUB, AND, OR) | 1 cycle |
| IIC_ALU_MEM | ALU operations with memory operand | 2-4 cycles |
| IIC_LOAD | Memory load operations | 4 cycles |
| IIC_STORE | Memory store operations | 2 cycles |
| IIC_BRANCH | Branch instructions | 2 cycles |
| IIC_CALL | Function call instructions | 3 cycles |
| IIC_RET | Return instructions | 3 cycles |
| IIC_FPU | Floating-point operations | 4 cycles |
| IIC_SHIFT | Bit shift operations | 1 cycle |
| IIC_MULTIPLY | Integer multiplication | 3 cycles |
| IIC_DIVIDE | Integer division | 10 cycles |
| IIC_DEFAULT | Default for unclassified instructions | 1 cycle |

## Implementation Details

### Current Status

- **CompleteModel = 0**: The model is currently marked as incomplete
- **TODO(m68k_sched)**: Transition to CompleteModel = 1 once all opcodes have scheduling info

### Known Missing Instructions

**Update July 21, 2025, 14:00 EEST**: Major scheduling improvements completed:

**Phase 1 - Critical Release Build Instructions** ✅:
- ✅ UMULd32d32, UMULd32i16 (unsigned multiply) - Added IIC_MULTIPLY
- ✅ UNLK (stack frame unlink) - Added IIC_ALU
- ✅ XOR variants (all operand types) - Added IIC_ALU

**Phase 2 - Enhanced Coverage** ✅:
- ✅ SUB variants (dd, di, dr) - Added IIC_ALU via MxBiArOp_R_RR_xEA
- ✅ SUB memory variants (dk, dp, dq) - Added IIC_ALU_MEM via MxBiArOp_R_RM
- ✅ SUBX (subtract with extend) - Added IIC_ALU via MxBiArOp_R_RRX
- ✅ TRAP, TRAPV (trap instructions) - Added IIC_BRANCH

**Release Builds**: Fully working with all optimization levels!

**Remaining Work for CompleteModel=1**:
- Pseudo instructions (COPY, ADJCALLSTACK*, CMOV*)
- MOV variants for condition codes (MOV*c)
- MOVM (move multiple) instructions
- Sign/zero extension pseudos (MOVSX*, MOVZX*)
- Frame handling (CFI_INSTRUCTION, EH_LABEL)
- Other specialized pseudo operations

These remaining instructions are not required for basic Rust compilation.

### Release Mode Issues

Release builds expose missing scheduling information because:
1. Optimizations generate more complex instruction sequences
2. Intrinsics in compiler_builtins use specialized instructions
3. Instruction combining creates variants not seen in debug builds

## Future Work

### Phase 1: Complete Basic Coverage (High Priority)
- Add scheduling info for all arithmetic instructions
- Cover all addressing mode variants
- Implement proper multiply/divide timing

### Phase 2: Processor-Specific Tuning (Medium Priority)
- Refine cycle counts based on M68k processor manuals
- Add separate Load/Store functional units
- Model cache effects for 68030/68040

### Phase 3: Advanced Features (Low Priority)
- Model M68040's dual-instruction pipeline
- Add memory barrier scheduling
- Implement prefetch modeling

## Testing

### Regression Test
```bash
# Basic compilation test
./ci/scripts/test-m68k-regression.sh

# All CPU models test
./ci/scripts/test-all-cpu-models.sh
```

### Debugging Missing Scheduling Info
```bash
# Temporarily enable complete model checking
# Edit M68kSchedule.td: CompleteModel = 1
./ci/scripts/build-custom-llvm.sh

# Use LLVM debug flags
RUSTFLAGS="-C llvm-args=--debug-only=isel" cargo build
```

## References

- [LLVM Scheduling Model Documentation](https://llvm.org/docs/WritingAnLLVMBackend.html#instruction-scheduling)
- [M68040 User's Manual](https://www.nxp.com/docs/en/user-guide/M68040UM.pdf) - Instruction timing reference
- [M68030 User's Manual](https://www.nxp.com/docs/en/reference-manual/M68030UM.pdf) - Instruction timing reference

## Contributing

When adding new instructions to the M68k backend:
1. Always include scheduling information in the instruction definition
2. Test with both debug and release builds
3. Verify with `CompleteModel = 1` before committing
4. Update this document with any new itinerary classes

---

*This document is part of the NeXTRust project documentation.*