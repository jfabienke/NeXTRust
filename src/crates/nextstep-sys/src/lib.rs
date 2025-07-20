//! nextstep-sys - Minimal NeXTSTEP system call bindings
//! 
//! Provides raw FFI bindings to NeXTSTEP system calls via trap #0

#![no_std]
#![allow(non_camel_case_types)]

use core::ffi::c_void;

// File descriptors
pub const STDIN_FILENO: i32 = 0;
pub const STDOUT_FILENO: i32 = 1;
pub const STDERR_FILENO: i32 = 2;

// System call numbers for trap #0
pub const SYS_EXIT: i32 = 1;
pub const SYS_WRITE: i32 = 4;
pub const SYS_GETPID: i32 = 20;

// Raw system call interface
#[link(name = "System")]
extern "C" {
    /// Write to a file descriptor
    /// fd: file descriptor
    /// buf: pointer to data
    /// count: number of bytes to write
    /// Returns: number of bytes written or -1 on error
    pub fn write(fd: i32, buf: *const u8, count: usize) -> isize;
    
    /// Exit the process
    /// status: exit code
    /// Never returns
    pub fn _exit(status: i32) -> !;
    
    /// Get process ID
    /// Returns: current process ID
    pub fn getpid() -> i32;
}

/// Safe wrapper for write syscall
#[inline]
pub fn sys_write(fd: i32, data: &[u8]) -> Result<usize, i32> {
    let ret = unsafe { write(fd, data.as_ptr(), data.len()) };
    if ret < 0 {
        Err(-1)
    } else {
        Ok(ret as usize)
    }
}

/// Safe wrapper for exit syscall
#[inline]
pub fn sys_exit(code: i32) -> ! {
    unsafe { _exit(code) }
}

/// Safe wrapper for getpid syscall
#[inline] 
pub fn sys_getpid() -> i32 {
    unsafe { getpid() }
}