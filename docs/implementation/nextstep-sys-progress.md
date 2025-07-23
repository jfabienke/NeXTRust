# nextstep-sys Implementation Progress

**Last Updated**: July 21, 2025, 10:45 PM EEST

## Overview

The `nextstep-sys` crate provides raw FFI bindings to NeXTSTEP system calls. It serves as the foundation for building higher-level Rust abstractions and eventually the standard library support.

## Implementation Status

### ✅ Completed

1. **Type Definitions**
   - Basic C types (c_int, size_t, pid_t, etc.)
   - NeXTSTEP-specific types (vm_offset_t, mach_port_t, etc.)
   - Type sizes match M68k 32-bit big-endian architecture

2. **System Call Numbers**
   - POSIX-compatible syscalls (1-200+)
   - Mach VM syscalls (negative numbers)
   - Verified against NeXTSTEP headers

3. **Constants**
   - File flags (O_RDONLY, O_RDWR, etc.)
   - File modes (S_IRUSR, S_IWUSR, etc.)
   - Error codes (EPERM through EPIPE)
   - Signals (SIGHUP through SIGTERM)
   - Mach VM protection flags
   - mmap constants

4. **Structures**
   - `struct stat` - File status
   - `struct timeval` - Time values
   - `struct timezone` - Timezone info
   - `struct dirent` - Directory entries
   - `struct iovec` - Scatter/gather I/O
   - `struct rusage` - Resource usage

5. **System Call Declarations**
   - Process control (fork, exec, wait, etc.)
   - File I/O (open, read, write, close, etc.)
   - File operations (stat, chmod, chown, etc.)
   - Directory operations (mkdir, rmdir, chdir, etc.)
   - Memory operations (mmap, munmap, sbrk, etc.)
   - Mach VM operations (vm_allocate, vm_deallocate, etc.)

6. **Safe Wrappers**
   - sys_write() - Write to file descriptor
   - sys_read() - Read from file descriptor
   - sys_open() - Open file
   - sys_close() - Close file descriptor
   - sys_exit() - Exit process
   - sys_getpid() - Get process ID
   - sys_vm_allocate() - Allocate virtual memory
   - sys_vm_deallocate() - Deallocate virtual memory

7. **Helper Functions**
   - WIFEXITED() - Check if process exited normally
   - WEXITSTATUS() - Get exit status
   - WIFSIGNALED() - Check if process was signaled
   - WTERMSIG() - Get terminating signal

## Current Line Count

~516 lines of code (from ~61 originally)

## Architecture Decisions

1. **no_std Design**: The crate is `#![no_std]` to support bare-metal and kernel development

2. **Raw Pointers**: System call interfaces use raw pointers matching the C ABI

3. **Error Handling**: Safe wrappers return `Result<T, i32>` with error codes

4. **Inline Functions**: All wrappers are `#[inline]` for zero-cost abstractions

5. **FFI Safety**: All extern functions properly match NeXTSTEP C signatures

## Next Steps

1. **Testing**: Create comprehensive test suite once custom rustc is ready

2. **Documentation**: Add detailed docs for each system call

3. **Additional Wrappers**: Implement safe wrappers for remaining syscalls

4. **Validation**: Verify all constants against actual NeXTSTEP headers

5. **Integration**: Use in higher-level crates (alloc support, I/O, etc.)

## Dependencies

- Requires custom rustc with M68k scheduling patches
- Links against NeXTSTEP System library
- No Rust dependencies (pure FFI bindings)

## Known Issues

1. **Snake Case Warnings**: Macro-style functions (WIFEXITED, etc.) trigger warnings
2. **Atomics**: No atomic operations yet (needed for pre-68020 support)
3. **Verification**: Constants need validation against real NeXTSTEP headers

## Usage Example

```rust
#![no_std]
#![no_main]

use nextstep_sys::*;

#[no_mangle]
pub extern "C" fn main() -> i32 {
    let msg = b"Hello from NeXTSTEP!\n";
    match sys_write(STDOUT_FILENO, msg) {
        Ok(n) => 0,
        Err(e) => e,
    }
}
```

This forms the foundation for building Rust std library support for NeXTSTEP.