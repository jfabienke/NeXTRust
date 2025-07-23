# Motorola 68000 Family Instruction Set Evolution

*Last Updated: 2025-07-23 09:22 EEST*

## Overview

The Motorola 68000 family represents one of the most successful CISC architectures in computing history, powering everything from the original Macintosh to Amiga, Atari ST, and many UNIX workstations. This document traces the evolution of the instruction set from the original 68000 through to modern implementations like the Apollo 68080.

## Processor Timeline

| Year | Model | Key Features | Target Market |
|------|-------|--------------|---------------|
| 1979 | 68000 | 16/32-bit hybrid, 7.16 MHz | Personal computers |
| 1982 | 68010 | Virtual memory, loop mode | Workstations |
| 1984 | 68020 | Full 32-bit, coprocessor interface | High-end workstations |
| 1987 | 68030 | On-chip MMU, data cache | UNIX systems |
| 1990 | 68040 | Integrated FPU, dual caches | Graphics workstations |
| 1994 | 68060 | Superscalar, branch prediction | Embedded systems |
| 2017 | Apollo 68080 | AMMX SIMD, 64-bit ops | FPGA retro-computing |

## Detailed Evolution by Processor

### 68000 (1979) - The Foundation

**Architecture:**
- 32-bit internal architecture with 16-bit data bus
- 24-bit address bus (16 MB address space)
- 8 data registers (D0-D7) and 7 address registers (A0-A6) + stack pointer (A7)
- 56 basic instructions

**Key Instructions Introduced:**
- Basic arithmetic: ADD, SUB, MUL, DIV
- Logical operations: AND, OR, EOR, NOT
- Shifts and rotates: ASL/ASR, LSL/LSR, ROL/ROR, ROXL/ROXR
- Data movement: MOVE, MOVEA, MOVEQ, MOVEM, MOVEP
- Program control: Bcc, DBcc, JMP, JSR, RTS
- Special: TRAP, CHK, TAS (Test and Set)

**Notable Features:**
- Sophisticated addressing modes (14 types)
- Orthogonal instruction set
- Condition code register (CCR)
- Supervisor/User modes

### 68010 (1982) - Virtual Memory Support

**New Features:**
- **Loop Mode**: Small loops execute from prefetch queue
- **Virtual Memory**: Instruction continuation after bus fault
- **Vector Base Register (VBR)**: Relocatable exception vectors

**New Instructions:**
- MOVEC: Move to/from control registers
- MOVES: Move to/from address space
- RTD: Return and deallocate parameters
- BKPT: Breakpoint instruction

**Removed Features:**
- None (fully backward compatible)

### 68020 (1984) - True 32-Bit Architecture

**Major Enhancements:**
- Full 32-bit data and address buses
- 4 GB address space
- 256-byte instruction cache
- Coprocessor interface

**New Addressing Modes:**
- Memory indirect with pre/post indexing
- Scaled index (2, 4, or 8)
- 32-bit displacements

**New Instructions:**
- **Bitfield operations**: BFCHG, BFCLR, BFEXTS, BFEXTU, BFFFO, BFINS, BFSET, BFTST
- **Enhanced multiply/divide**: 32x32→64 multiply, 64÷32→32 divide
- **Link/Unlink**: LINK with 32-bit displacement
- **Compare**: CMP2, CHK2 (bound checking)
- **Pack/Unpack**: PACK, UNPK (BCD operations)
- **Module support**: CALLM, RTM (removed in later processors)
- **CAS**: Compare and Swap (atomic operation)
- **CAS2**: Double Compare and Swap
- **TRAPcc**: Conditional trap

### 68030 (1987) - Integrated Memory Management

**Hardware Enhancements:**
- On-chip MMU (from 68851)
- 256-byte data cache (in addition to instruction cache)
- Burst mode memory access
- Dynamic bus sizing

**MMU Instructions (from 68851):**
- PFLUSH: Flush ATC entries
- PFLUSHA: Flush all ATC entries
- PLOAD: Load ATC entry
- PMOVE: Move to/from MMU registers
- PTEST: Test logical address

**New Features:**
- No new general-purpose instructions
- Enhanced performance (50% faster than 68020 at same clock)

### 68040 (1990) - Integration and Pipelines

**Revolutionary Changes:**
- 6-stage pipeline architecture
- Integrated FPU (but simplified)
- 4KB instruction cache, 4KB data cache
- Copyback cache mode

**New Instructions:**
- MOVE16: Move 16-byte aligned blocks (cache line size)
- CINV: Cache invalidate
- CPUSH: Cache push (flush)

**FPU Changes - Critical:**
- **Transcendentals REMOVED**: FSIN, FCOS, FTAN, FSINCOS, FASIN, FACOS, FATAN, FATANH, FSINH, FCOSH, FTANH
- **Also REMOVED**: FLOGN, FLOGNP1, FLOG10, FLOG2, FETOX, FETOXM1, FTWOTOX, FTENTOX
- **Simplified**: Only basic FP operations remain (FADD, FSUB, FMUL, FDIV, FSQRT, etc.)
- **Reason**: Simplified FPU design for integration, transcendentals trap to software

### 68060 (1994) - Superscalar Performance

**Architecture Revolution:**
- Dual instruction pipelines (superscalar)
- Can execute 2 instructions per clock
- Branch prediction
- 8KB I-cache, 8KB D-cache

**Removed Integer Instructions:**
- MOVEP: Move peripheral (for 8-bit buses)
- CAS2: Double compare and swap
- CHK2, CMP2: Bounds checking
- 64-bit multiply/divide operations
- CALLM, RTM: Module operations (were rarely used)

**Additional FPU Removals (beyond 68040):**
- Packed decimal operations (FMOVEP, etc.)
- Some FP conversions
- FMOD, FREM: Modulo operations
- FSCALE: Scale by power of 2
- FGETEXP, FGETMAN: Get exponent/mantissa

**Performance Focus:**
- Simple instructions execute in 1 cycle
- Most common operations optimized
- Complex operations trap to software (M68060SP)

### Apollo 68080 (2017+) - Modern Revival

**FPGA Implementation with Modern Features:**
- Backward compatible with 68060
- 64-bit operations (some)
- AMMX: Apollo/Motorola Multimedia Extensions

**AMMX Instructions (SIMD):**
- 64-bit loads/stores: LOAD, STORE
- Parallel operations: PADD, PSUB, PMUL
- Saturating arithmetic: PADDSAT, PSUBSAT
- Byte/word operations: 8x8-bit or 4x16-bit parallel
- Permutation: PPERM, PERM
- Min/Max: PMIN, PMAX
- Transformations: TRANSHI, TRANSLO

**Modern Enhancements:**
- Improved pipeline (can execute more instructions per clock)
- Better branch prediction
- Larger caches
- Higher clock speeds possible in FPGA

## Summary Comparison Table

| Feature | 68000 | 68010 | 68020 | 68030 | 68040 | 68060 | Apollo 68080 |
|---------|-------|-------|-------|-------|-------|-------|--------------|
| Data Bus | 16-bit | 16-bit | 32-bit | 32-bit | 32-bit | 32-bit | 32-bit |
| Address Bus | 24-bit | 24-bit | 32-bit | 32-bit | 32-bit | 32-bit | 32-bit |
| FPU | External | External | External | External | Integrated* | Integrated* | Enhanced |
| MMU | None | None | External | Integrated | Integrated | Integrated | Integrated |
| I-Cache | None | Loop mode | 256B | 256B | 4KB | 8KB | Larger |
| D-Cache | None | None | None | 256B | 4KB | 8KB | Larger |
| Pipeline | None | None | 3-stage | 3-stage | 6-stage | Dual 4-stage | Enhanced |
| Bitfield Ops | No | No | Yes | Yes | Yes | Yes | Yes |
| CAS | No | No | Yes | Yes | Yes | Yes | Yes |
| CAS2 | No | No | Yes | Yes | Yes | No** | No |
| MOVE16 | No | No | No | No | Yes | Yes | Yes |
| Transcendentals | N/A | N/A | Ext. FPU | Ext. FPU | No** | No** | Software |
| SIMD | No | No | No | No | No | No | AMMX |

\* Integrated but with reduced instruction set
\*\* Removed - traps to software emulation

## Instruction Count Evolution

| Processor | Basic Integer | FPU | MMU | Special | Total (approx) |
|-----------|--------------|-----|-----|---------|----------------|
| 68000 | 56 | 0 | 0 | 0 | 56 |
| 68010 | 60 | 0 | 0 | 0 | 60 |
| 68020 | 100+ | 0 | 0 | 11 | 111+ |
| 68030 | 100+ | 0 | 5 | 11 | 116+ |
| 68040 | 102+ | 25 | 8 | 11 | 146+ |
| 68060 | 95 | 18 | 8 | 11 | 132 |
| 68080 | 95 | 18 | 8 | 30+ | 151+ |

## Key Insights

1. **Backward Compatibility**: Each processor maintained compatibility while adding features
2. **Integration Trend**: External chips (FPU, MMU) became integrated over time
3. **Performance vs Completeness**: Later models (68040+) removed complex instructions for speed
4. **Market Evolution**: From computers to embedded systems to FPGA implementations
5. **CISC to RISC-like**: Evolution toward simpler, faster instructions
6. **Software Emulation**: Complex operations moved from hardware to software

## Programming Implications

### For Assembly Programmers
- Check CPU type before using newer instructions
- Have fallback code for removed instructions
- Use CPU-specific optimizations where beneficial
- Consider instruction timing differences

### For Compiler Writers
- Generate CPU-specific code paths
- Avoid removed instructions on 68060
- Use MOVE16 for block copies on 68040+
- Leverage AMMX on Apollo 68080

### For OS Developers
- Install exception handlers for emulated instructions
- Provide FPU emulation libraries
- Optimize for cache line sizes
- Handle CPU-specific MMU features

## References

- [Motorola M68000 Family Programmer's Reference Manual](../references/M68000PRM.pdf)
- [Motorola MC68060 User's Manual](../references/MC68060UM.pdf)
- Individual processor user manuals (68000-68060)
- Apollo 68080 Core Documentation
- [Apollo Core 68080 Programmer's Reference Manual](../references/AC68080PRM.pdf)
- "The 68000 Microprocessor" by James L. Antonakos
- Various Motorola technical notes and application notes

## See Also

- [M68k ISA Evolution for LLVM](../llvm-enhancements/m68k-isa-evolution-llvm.md)
- [M68060 Removed Instructions](../llvm-enhancements/m68060-removed-instructions.md)
- [M68k Instruction Implementation Status](../llvm-enhancements/m68k-instruction-set-status.md)