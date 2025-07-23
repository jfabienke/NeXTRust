# M68k Emulator Compatibility Guide

*Last Updated: July 23, 2025 08:09 EEST*

## Overview

This guide documents the M68k CPU emulation capabilities of various emulators relevant to the NeXTRust project, with a focus on instruction set completeness and compatibility for testing LLVM-generated code.

## Emulator Comparison

### Previous (NeXT-specific Emulator)

**CPU Core**: WinUAE (by Toni Wilen) with 68030 MMU by andreas_g  
**Status**: Most complete and accurate for NeXT hardware

#### Capabilities
- **68030 Support**: Full implementation with integrated MMU
- **68040 Support**: Full implementation with integrated MMU and FPU
- **FPU**: Near-complete 68881/68882 and 68040 FPU emulation
- **MMU**: Full MMU emulation for both processors
- **Accuracy**: Cycle-exact timing, undocumented behavior support
- **Testing**: Can boot all NeXTSTEP/OPENSTEP versions

#### Known Issues
- Minor platform-sensitive FPU edge cases
- Timing differs from real hardware (expected in emulation)

#### Recommendation
✅ **Primary testing target for NeXTRust** - Most accurate NeXT emulation available

### WinUAE (Previous's CPU Core Source)

**Status**: Reference implementation for 68k emulation

#### Capabilities
- **68030**: "Almost complete" implementation
- **68040**: "Almost complete" (only MOVE16 unaligned behavior issue)
- **68060**: Full support including removed instruction emulation
- **Testing**: Comprehensive CPU tester validates all operations
- **Features**: Full cycle counting, exception handling, stack frames

#### Special Features
- Validates all registers and flags
- Tests undocumented instructions
- Includes MMU emulation (non-JIT mode)
- Most thorough 68k test suite available

### MAME

**Status**: Good but with known limitations

#### Capabilities
- **CPU Support**: 68000, 68010, 68020, 68EC020, 68030, 68EC030, 68040, 68EC040
- **Basic Operations**: Full support for standard instructions
- **FPU**: Improved but still has issues

#### Known Limitations
- 68040 runs with 68030-like cycle timings
- FPU emulation prevents some software (Marathon) from running
- Some undocumented instructions not implemented
- MOVES instruction space needs improvement
- Cannot boot A/UX (unknown cause)

#### Recommendation
⚠️ **Secondary testing option** - Good for basic verification but not cycle-accurate

### Musashi

**Status**: Mature, portable implementation

#### Capabilities
- **CPU Support**: Full 68030, 68040, and EC variants
- **FPU**: 68040 FPU emulation (requires libm)
- **Portability**: Clean C implementation, easy to integrate

#### Known Limitations
- Serious MMU emulation limitations
- Less accurate than WinUAE
- No cycle-exact timing

#### Usage
Used in various projects including MAME for some systems

## Instruction Set Coverage

### Complete in All Major Emulators
- Basic integer arithmetic (ADD, SUB, MUL, DIV)
- Logical operations (AND, OR, XOR, NOT)
- Shifts and rotates (ASL, ASR, LSL, LSR, ROL, ROR)
- Basic control flow (Bcc, JMP, JSR, RTS)
- Data movement (MOVE, LEA)
- Basic FPU operations (FADD, FSUB, FMUL, FDIV)

### Emulator-Specific Differences

#### Previous/WinUAE
- ✅ All 68030/68040 instructions including:
  - Complex addressing modes
  - MOVEM, MOVEP
  - CAS, CAS2 (on 68030)
  - Full FPU transcendentals
  - MMU instructions

#### MAME
- ⚠️ Missing or incomplete:
  - Some undocumented opcodes
  - Full FPU accuracy
  - Precise 68040 timing

## Testing Recommendations

### 1. Primary Testing (Previous)
```bash
# Test basic functionality
previous -c config.cfg test.prg

# Enable CPU debugging
previous --debug --cpu-log test.prg
```

### 2. Cross-Validation
- Build code with LLVM
- Test first on Previous
- Validate on MAME if needed
- Final test on real hardware (if available)

### 3. Instruction Subset Testing
For maximum compatibility, limit to:
- Basic integer operations
- Simple addressing modes
- Standard control flow
- No complex FPU operations

### 4. 68060 Considerations
When targeting 68060:
- Avoid removed instructions (see m68060-removed-instructions.md)
- Previous emulates M68060SP behavior
- Test with 68060 mode enabled

## LLVM Code Generation Guidelines

### For Maximum Emulator Compatibility

1. **Use Conservative Instruction Selection**
   ```llvm
   ; Prefer simple addressing modes
   ; Avoid complex ea calculations
   ```

2. **Avoid Edge Cases**
   - Misaligned CAS operations
   - Undocumented opcodes
   - Complex FPU operations on MAME

3. **Test Incrementally**
   - Start with integer-only code
   - Add FPU operations gradually
   - Test each new instruction pattern

### Emulator-Specific Workarounds

#### MAME Issues
```c
// Avoid FPU transcendentals if targeting MAME
#ifdef TARGET_MAME
  // Use software implementation
#else
  // Use hardware FPU
#endif
```

#### Timing-Sensitive Code
```c
// Don't rely on cycle-exact timing
// Use timer interrupts instead of busy loops
```

## Debugging Features

### Previous
- CPU state logging
- Instruction trace
- Memory watchpoints
- MMU translation logs

### WinUAE
- Comprehensive debugger
- CPU validation mode
- Cycle counting
- Exception tracking

### MAME
- Standard MAME debugger
- Memory inspection
- Basic breakpoints

## Performance Considerations

### Emulation vs Hardware
| Operation | Hardware | Previous | MAME |
|-----------|----------|----------|------|
| Basic ALU | 1 cycle | ~1-2 host | ~2-4 host |
| Memory Access | 2-4 cycles | ~5-10 host | ~10-20 host |
| FPU Op | 4-40 cycles | ~20-100 host | ~50-200 host |

Note: "host" refers to modern CPU instructions

### JIT vs Interpretation
- Previous: Interpreted (accurate)
- Some MAME builds: JIT available (faster, less accurate)
- Recommendation: Use interpreted mode for testing

## Best Practices

1. **Start with Previous** - Most accurate for NeXT
2. **Validate on Multiple Emulators** - Catches edge cases
3. **Use Simple Instructions** - Maximum compatibility
4. **Test Incrementally** - Isolate issues quickly
5. **Document Emulator-Specific Issues** - Help future developers

## Troubleshooting

### Common Issues

1. **Code runs on Previous but not MAME**
   - Check for FPU usage
   - Verify instruction subset
   - Look for timing dependencies

2. **Different behavior between emulators**
   - Check flag handling
   - Verify addressing mode edge cases
   - Compare exception behavior

3. **Crashes on real hardware**
   - MMU configuration issues
   - Uninitialized memory access
   - Timing-dependent code

## Summary

For the NeXTRust project:
1. **Previous is the gold standard** for testing
2. **LLVM output should work on all emulators** with basic instruction set
3. **Avoid emulator-specific features** for maximum portability
4. **Test thoroughly** before claiming hardware compatibility

## See Also

- [M68k Instruction Set Status](m68k-instruction-set-status.md)
- [M68060 Removed Instructions](m68060-removed-instructions.md)
- [Previous Emulator Documentation](http://previous.alternative-system.com/)
- [WinUAE CPU Core](https://github.com/tonioni/WinUAE)