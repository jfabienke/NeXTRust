# Rust Target Specification for m68k-next-nextstep

*Last updated: 2025-07-15 10:20 AM*

## Overview

This document defines the Rust target specification for `m68k-next-nextstep`, enabling cross-compilation from modern systems to NeXTSTEP running on Motorola 68k processors. The target aims for Tier 3 support in the Rust compiler, providing a foundation for running Rust applications on vintage NeXT hardware.

## Target Triple

```
m68k-next-nextstep
```

### Components
- **Architecture**: `m68k` - Motorola 68000 series processors
- **Vendor**: `next` - NeXT Computer, Inc.
- **OS**: `nextstep` - NeXTSTEP operating system

## Target Specification JSON

```json
{
  "arch": "m68k",
  "os": "nextstep",
  "vendor": "next",
  "linker-flavor": "ld",
  "data-layout": "E-m:e-p:32:32-i64:64-n8:16:32",
  "llvm-target": "m68k-next-nextstep",
  "executables": true,
  "has-rpath": false,
  "has-elf-tls": false,
  "panic-strategy": "abort",
  "relocation-model": "static",
  "code-model": "large",
  "function-sections": false,
  "is-builtin": false,
  "min-atomic-width": 8,
  "max-atomic-width": 32,
  "atomic-cas": false,
  "features": "+68030",
  "dynamic-linking": true,
  "os-family": "unix",
  "abi-return-struct-as-int": true,
  "emit-debug-gdb-scripts": false,
  "requires-uwtable": false,
  "default-hidden-visibility": false,
  "exe-suffix": "",
  "staticlib-suffix": ".a",
  "dll-suffix": ".so",
  "archive-format": "bsd",
  "pre-link-args": {
    "ld": [
      "-arch",
      "m68k",
      "-macosx_version_min",
      "10.0"
    ]
  },
  "late-link-args": {
    "ld": [
      "-lSystem"
    ]
  }
}
```

## Data Layout Explanation

```
E-m:e-p:32:32-i64:64-n8:16:32
```

- **E**: Big-endian byte order (m68k is big-endian)
- **m:e**: ELF name mangling (adapted for Mach-O)
- **p:32:32**: 32-bit pointers with 32-bit alignment
- **i64:64**: 64-bit integers with 64-bit alignment
- **n8:16:32**: Native integer widths of 8, 16, and 32 bits

## CPU Features

### Base Configuration
- **+68030**: Default CPU target (NeXTcube/NeXTstation base model)
- **+68040**: Optional for Turbo models
- **+68882**: FPU support (external on 68030, integrated on 68040)

### Feature Flags
```rust
// Compile for 68040 with FPU
#[cfg(target_feature = "68040")]
#[cfg(target_feature = "fpu")]
fn optimized_math() {
    // Uses hardware floating point
}

// Fallback for 68030
#[cfg(not(target_feature = "68040"))]
fn optimized_math() {
    // Software floating point emulation
}
```

## ABI Specifications

### Calling Convention
- **Register usage**:
  - `d0-d1`: Return values
  - `d0-d2`, `a0-a1`: Function arguments
  - `d3-d7`, `a2-a5`: Callee-saved
  - `a6`: Frame pointer
  - `a7`: Stack pointer

### Stack Layout
- **Growth direction**: Downward (decreasing addresses)
- **Alignment**: 16-byte alignment for stack frames
- **Red zone**: None (NeXTSTEP doesn't guarantee red zone)

### Structure Passing
- Structures d 8 bytes: Passed in registers
- Structures > 8 bytes: Passed by reference
- Return structures: Via hidden first parameter

## Atomic Operations

Since m68k lacks native compare-and-swap (CAS) instructions:

```rust
// Spinlock-based atomic implementation
pub struct AtomicBool {
    v: UnsafeCell<u8>,
}

impl AtomicBool {
    pub fn store(&self, val: bool, _order: Ordering) {
        unsafe {
            // Disable interrupts
            asm!("ori #0x0700, sr");
            
            // Store value
            *self.v.get() = val as u8;
            
            // Enable interrupts
            asm!("andi #0xF8FF, sr");
        }
    }
}
```

## System Call Interface

### Trap Instructions
- **Trap #0**: Mach system calls
- **Trap #1**: BSD compatibility system calls
- **Trap #2**: NeXT-specific services

### Example System Call
```rust
// Write to console using trap #0
unsafe fn write_console(msg: &str) {
    asm!(
        "move.l {msg}, -(sp)",     // Push message pointer
        "move.l {len}, -(sp)",     // Push length
        "move.w #4, -(sp)",        // System call number (write)
        "trap #0",                 // Invoke Mach syscall
        "add.l #10, sp",           // Clean up stack
        msg = in(reg) msg.as_ptr(),
        len = in(reg) msg.len(),
        clobber_abi("C"),
    );
}
```

## Memory Model

### Address Space
- **32-bit virtual addresses**: 4GB theoretical limit
- **Segmented layout**:
  - Text segment: 0x4000 - 0x10000
  - Data segment: Following text
  - Stack: Top of address space growing down
  - Heap: After data segment growing up

### Large Code Model
Required for programs exceeding 64KB due to:
- Limited PC-relative addressing range
- Separate ROM/RAM layouts in some configurations
- Need for 32-bit absolute addresses

## Linking and Object Format

### Mach-O Specifics
- **File format**: NeXT Mach-O (vintage variant)
- **Segments**: `__TEXT`, `__DATA`, `__OBJC`
- **Load commands**: Subset of modern Mach-O
- **Symbol table**: BSD-style with NeXT extensions

### Dynamic Linking
- **Shared libraries**: `.so` suffix (predates `.dylib`)
- **Runtime loader**: `/usr/lib/dyld` (early version)
- **Symbol resolution**: Two-level namespace

## Standard Library Support

### Core Library
- Full support via `-Z build-std=core`
- No heap allocation required
- Panic handler must be provided

### Alloc Library
- Requires implementing GlobalAlloc
- Uses `vm_allocate` Mach calls

### Std Library
- Partial support planned
- Key components:
  - I/O via BSD compatibility layer
  - Threads via Mach threads
  - Time via Mach absolute time
  - Network via BSD sockets

## Build Configuration

### Cargo Configuration
```toml
# .cargo/config.toml
[target.m68k-next-nextstep]
linker = "m68k-next-nextstep-ld"
ar = "m68k-next-nextstep-ar"
rustflags = [
    "-C", "code-model=large",
    "-C", "relocation-model=static",
    "-C", "panic=abort",
]

[build]
target = "m68k-next-nextstep"
```

### Build Command
```bash
cargo +nightly build \
    --target m68k-next-nextstep \
    -Z build-std=core,alloc,std \
    -Z build-std-features=panic_immediate_abort
```

## Testing Strategy

### Emulation Testing
- Primary: Previous emulator
- Secondary: QEMU with experimental NeXT support
- Automated via CI pipeline

### Hardware Testing
- Optional for enthusiasts with real hardware
- ROM requirements: Rev 2.5 v66 or compatible
- Serial console for debugging output

## Known Limitations

1. **No native atomics**: All atomic operations use spinlocks
2. **Limited TLS**: No thread-local storage support
3. **Stack size**: Fixed at compile time (no growth)
4. **Debugger support**: Limited to serial gdb stub
5. **Unwinding**: No support (panic=abort only)

## Future Enhancements

1. **Inline assembly**: Stabilize m68k asm! syntax
2. **SIMD**: Explore 68040 data cache optimizations
3. **Profiling**: Port perf tools for cycle counting
4. **LTO**: Enable link-time optimization
5. **Split stacks**: Investigate segmented stack support

## References

- [Rust Platform Support](https://doc.rust-lang.org/nightly/rustc/platform-support.html)
- [LLVM M68k Backend](https://llvm.org/docs/CompilerWriterInfo.html#m68k)
- [NeXT Mach-O Format](http://www.cilinder.be/docs/next/NeXTStep/3.3/nd/DevTools/14_MachO/MachO.htmld/)
- [Motorola 68030 User's Manual](https://www.nxp.com/docs/en/reference-manual/MC68030UM.pdf)