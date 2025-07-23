# M68060 Removed Instructions

*Last Updated: July 23, 2025 08:08 EEST*

## Overview

The Motorola 68060 processor, while being the most advanced member of the 68k family, actually removed several instructions that were present in earlier models (68040 and prior). This was done to enable the superscalar architecture that allows the 68060 to execute multiple instructions per clock cycle.

## Why Instructions Were Removed

The 68060 was designed with a dual-pipeline superscalar architecture, capable of executing:
- One integer instruction per pipeline (2 total) per clock cycle
- One floating-point instruction in parallel with integer operations

To achieve this performance, Motorola:
- Simplified the instruction decoder
- Removed complex multi-cycle instructions
- Eliminated rarely-used instructions
- Streamlined the execution units

The removed instructions are handled through exception processing and software emulation, maintaining backward compatibility while achieving 3-4x performance improvement over the 68040 at the same clock speed.

## Unimplemented Integer Instructions

### 1. MOVEP (Move Peripheral Data)
- **Opcodes**: MOVEP.W, MOVEP.L
- **Purpose**: Transfers data to/from peripherals on 8-bit buses
- **Reason for removal**: Rarely used in modern 32-bit systems

### 2. CAS2 (Compare and Swap Double)
- **Opcodes**: CAS2.W, CAS2.L
- **Purpose**: Atomic operation on two memory locations
- **Reason for removal**: Complex implementation, rarely used
- **Note**: Single CAS instruction remains but generates exception on misaligned addresses

### 3. CHK2 (Check Register Against Bounds)
- **Opcodes**: CHK2.B, CHK2.W, CHK2.L
- **Purpose**: Checks if register value is within bounds
- **Reason for removal**: Complex bounds checking, better done in software

### 4. CMP2 (Compare Register Against Bounds)
- **Opcodes**: CMP2.B, CMP2.W, CMP2.L
- **Purpose**: Compares register against two bounds
- **Reason for removal**: Similar to CHK2, rarely used

### 5. 64-bit Integer Operations
- **DIVU.L** - 64-bit ÷ 32-bit → 32-bit quotient, 32-bit remainder
- **DIVS.L** - Signed version of above
- **MULU.L** - 32-bit × 32-bit → 64-bit product
- **MULS.L** - Signed version of above
- **Reason for removal**: Multi-cycle operations incompatible with pipeline

## Floating-Point Instruction History: 68040 vs 68060

### Important Historical Context

The story of missing FPU instructions actually begins with the **68040**, not the 68060:

#### 68881/68882 (External FPUs)
- **Full implementation**: These external FPUs implemented ALL floating-point instructions in hardware
- Transcendental functions executed directly in silicon
- Complete IEEE 754 support plus extensions

#### 68040 (First Integrated FPU)
- **Basic operations implemented**: ADD, SUB, MUL, DIV, compare, conversions
- **Transcendentals NOT implemented**: FSIN, FCOS, FTAN, etc. trap to F-line exception (vector #11)
- **Strategy**: Let OS emulate complex functions in software
- Most other FPU operations still supported in hardware

#### 68060 (Further Reduced)
- **Even more minimal**: Removed additional instructions beyond transcendentals
- **Also removed**: Packed decimal operations, some conversions
- **Goal**: Maximize performance for common operations, rely on software for rest

### FPU Implementation Comparison

| CPU | FPU Type | Basic Ops | Transcendentals | Packed Decimal | Other Complex |
|-----|----------|-----------|-----------------|----------------|---------------|
| 68881/68882 | External | ✅ Hardware | ✅ Hardware | ✅ Hardware | ✅ Hardware |
| 68040 | Integrated | ✅ Hardware | ❌ Traps | ✅ Hardware | ✅ Most in HW |
| 68060 | Integrated | ✅ Hardware | ❌ Traps | ❌ Traps | ❌ Many trap |

### Unimplemented Floating-Point Instructions

#### Transcendental Functions (Missing since 68040)
| Instruction | Operation | 68040 | 68060 |
|-------------|-----------|-------|-------|
| FSIN | Sine | Traps | Traps |
| FCOS | Cosine | Traps | Traps |
| FTAN | Tangent | Traps | Traps |
| FASIN | Arc sine | Traps | Traps |
| FACOS | Arc cosine | Traps | Traps |
| FATAN | Arc tangent | Traps | Traps |
| FATANH | Hyperbolic arc tangent | Traps | Traps |
| FSINH | Hyperbolic sine | Traps | Traps |
| FCOSH | Hyperbolic cosine | Traps | Traps |
| FTANH | Hyperbolic tangent | Traps | Traps |
| FSINCOS | Simultaneous sine and cosine | Traps | Traps |

#### Logarithmic and Exponential Functions (Missing since 68040)
| Instruction | Operation | 68040 | 68060 |
|-------------|-----------|-------|-------|
| FLOGN | Natural logarithm | Traps | Traps |
| FLOGNP1 | Natural logarithm of (x+1) | Traps | Traps |
| FLOG10 | Base 10 logarithm | Traps | Traps |
| FLOG2 | Base 2 logarithm | Traps | Traps |
| FETOX | e to the x power | Traps | Traps |
| FETOXM1 | e to the x power minus 1 | Traps | Traps |
| FTWOTOX | 2 to the x power | Traps | Traps |
| FTENTOX | 10 to the x power | Traps | Traps |

#### Additional Instructions Removed in 68060
| Instruction | Operation | 68040 | 68060 |
|-------------|-----------|-------|-------|
| FMOD | Modulo remainder | Traps | Traps |
| FREM | IEEE remainder | Traps | Traps |
| FSCALE | Scale by power of 2 | Traps | Traps |
| FGETEXP | Get exponent | Traps | Traps |
| FGETMAN | Get mantissa | Traps | Traps |
| F*P | All packed decimal ops | ✅ Hardware | ❌ Traps |
| Various | Some FP conversions | ✅ Hardware | ❌ Traps |

### Key Takeaway

The 68040 started the trend of omitting complex FPU instructions (transcendentals), but the 68060 took it further by also removing packed decimal operations and other instructions that the 68040 still supported. This progressive simplification enabled:
- 68040: Integration of FPU on-chip while maintaining reasonable die size
- 68060: Superscalar execution with dual pipelines at the cost of more software emulation

## Exception Handling

### F-Line Exception (Vector #11)
- **68040/68060**: Unimplemented FPU instructions trigger F-line exception
- **Format**: Line 1111 binary pattern in opcode
- **Handler**: OS-provided emulation routine

### Integer Instructions  
- **Exception Vector**: #61 (Unimplemented Integer Instruction) - 68060 only
- **Stack Frame**: Contains instruction word and PC for emulation
- **Recovery**: Software emulation routine executes instruction

### Floating-Point Instructions
- **Exception**: F-line exception (vector #11) for unimplemented ops
- **Stack Frame**: Standard 68040/68060 exception frame format
- **Recovery**: FPU emulation package handles instruction

## Software Emulation

Motorola provides the **M68060SP (Software Package)** which includes:

1. **Integer Emulation Module** (I_CALL.S)
   - Handles all unimplemented integer instructions
   - Typical overhead: 100-200 cycles per instruction

2. **Floating-Point Emulation Module** (FP_CALL.S)
   - Implements all missing FPU instructions
   - Performance varies by operation (100-1000+ cycles)

3. **OS Integration**
   - Exception handlers must be installed
   - Transparent to user applications
   - No recompilation required

## LLVM Implementation Considerations

### For LLVM Code Generation

1. **Avoid Generating Removed Instructions**
   - Don't use MOVEP for peripheral access
   - Don't generate CAS2 for double atomics
   - Avoid CHK2/CMP2 for bounds checking
   - Don't use 64-bit multiply/divide variants

2. **Alternative Instruction Sequences**
   - MOVEP → Use normal MOVE instructions
   - CAS2 → Use two CAS instructions with locks
   - CHK2/CMP2 → Use CMP and Bcc sequences
   - 64-bit operations → Use 32-bit instruction sequences

3. **Feature Detection**
   ```tablegen
   // In M68k.td or similar
   def FeatureNo68060Removed : SubtargetFeature<
     "no-68060-removed", "Has68060RemovedInsns", "false",
     "CPU has instructions removed in 68060">;
   
   // Use in instruction definitions
   let Predicates = [FeatureNo68060Removed] in {
     def MOVEP : ... // Only generate for pre-68060
   }
   ```

## Performance Impact

### With Software Emulation
- Removed instructions: 100-1000+ cycles (emulated)
- Alternative sequences: 2-20 cycles (native)
- Overall impact: Minimal for typical code (<1% instructions removed)

### Superscalar Benefits
- Dual issue: Up to 2 instructions/cycle
- Better pipelining: Simpler instructions
- Net result: 3-4x faster than 68040 despite emulation

## Testing Considerations

When testing on emulators:
- **Previous/WinUAE**: Full emulation of all instructions
- **Real 68060**: Requires M68060SP installed
- **LLVM output**: Should avoid removed instructions for 68060 target

## Summary

The progressive simplification of FPU capabilities from 68881/68882 → 68040 → 68060 represents a successful evolution in CPU design:

### Historical Progression
1. **68881/68882**: Full hardware implementation of all FPU instructions
2. **68040**: First to remove transcendentals (trap to software), integrated FPU on-chip
3. **68060**: Further removed packed decimal and other ops for superscalar design

### Design Trade-offs
- **68040**: Balanced integration vs. functionality (kept most non-transcendental ops)
- **68060**: Prioritized performance over completeness (dual pipelines worth the trade-off)
- Both maintained full compatibility through software emulation
- Net result: Faster execution of common operations at the cost of rare ones

### LLVM Implications
For the NeXTRust project targeting 68040/68060:
- Transcendental functions will trap on both processors (use math libraries)
- Packed decimal operations will trap only on 68060
- Basic FPU operations (ADD, SUB, MUL, DIV) work on both
- Current LLVM implementation only has basic ops anyway, so no immediate concern

## References

- [Motorola MC68060 User's Manual](../references/MC68060UM.pdf)
- M68060 Software Package Documentation
- "Motorola 68060 Superscalar Microprocessor" technical papers

## See Also

- [M68k Instruction Set Status](m68k-instruction-set-status.md)
- [M68k Emulator Compatibility](m68k-emulator-compatibility.md)
- [M68k Scheduling Models](m68k-scheduling-complete.md)